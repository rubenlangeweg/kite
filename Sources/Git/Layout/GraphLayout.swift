import Foundation
import OSLog

/// Column-reuse DAG layout with first-parent preference.
///
/// This is the pure-function backbone of the M4 commit-graph milestone: given
/// a topo-ordered `[Commit]` (newest first — parents appear AFTER their
/// children on the wire), it returns a parallel `[LayoutRow]` with a lane
/// index assigned to each commit plus the in- and out-edge segments the
/// per-row `Canvas` renders.
///
/// Algorithm per `library/git-graph-rendering.md` §1:
///   1. Walk commits newest-first.
///   2. Maintain a `lanes: [String?]` vector where `lanes[i]` holds the SHA
///      that lane `i` is waiting on.
///   3. Place each commit in the leftmost lane expecting it; else in the
///      first free slot (or a new column).
///   4. Clear every lane waiting on the same SHA (branches converging in).
///   5. For the first parent, prefer to keep the commit's lane (keeps linear
///      chains and `main`-line descent in a consistent column — VAL-GRAPH-003).
///   6. For additional parents, join an existing waiting lane if the parent
///      is already expected; else use the first free slot.
///   7. For every through-lane (non-nil, untouched by this row), emit a
///      pair of in/out-edges drawing the vertical line passing by.
///
/// Complexity is O(N · L) where L is peak lane count; for the v1 200-commit
/// window this is well under 1ms on an M1.
///
/// Fulfills VAL-GRAPH-002, VAL-GRAPH-003, VAL-GRAPH-006.
enum GraphLayout {
    private static let logger = Logger(subsystem: "nl.rb2.kite", category: "layout")

    /// Compute the lane assignment and edge routing for a topo-ordered
    /// commit list. The input MUST be newest-first (as produced by
    /// `git log --all --topo-order ...`); passing a mixed order produces a
    /// correct but visually noisy layout.
    static func compute(_ commits: [Commit]) -> [LayoutRow] {
        if commits.isEmpty { return [] }

        // lanes[i] == SHA the lane is currently waiting to land on, or nil
        // (free slot). Grown on demand, shrunk opportunistically by trimming
        // trailing nils to keep it small for the next iteration.
        var lanes: [String?] = []
        var rows: [LayoutRow] = []
        rows.reserveCapacity(commits.count)

        for commit in commits {
            rows.append(processCommit(commit, lanes: &lanes))
            trimTrailingNils(&lanes)
        }

        return rows
    }

    // MARK: - Private

    /// Process a single commit against the evolving `lanes` vector and
    /// produce its `LayoutRow`. Mutates `lanes` in place.
    private static func processCommit(_ commit: Commit, lanes: inout [String?]) -> LayoutRow {
        let column = claimColumn(for: commit.sha, in: &lanes)
        let convergingColumns = consumeConvergingLanes(for: commit.sha, column: column, in: &lanes)

        // In-edges: every converging column feeds the commit's dot. Color is
        // seeded from the commit SHA so a merge's incoming strands read as
        // "the branch that arrived here".
        let commitSeedColor = LanePalette.color(for: commit.sha)
        var inEdges = convergingColumns.map { source in
            LaneEdge(fromColumn: source, toColumn: column, color: commitSeedColor)
        }

        let parentColumns = placeParents(commit.parents, commitColumn: column, in: &lanes)

        if commit.parents.count > 2 {
            // Octopus merges are rare but legitimate (Linux kernel subtree
            // merges). Straight-line fallback per library §2 and
            // VAL-GRAPH-006; log for observability.
            logger.debug(
                "octopus merge encountered: \(commit.sha, privacy: .public) has \(commit.parents.count) parents"
            )
        }

        // Out-edges: one per parent, coloured by the parent's SHA so each
        // descending strand reads as "that branch's color".
        var outEdges: [LaneEdge] = []
        outEdges.reserveCapacity(parentColumns.count)
        for (index, parentColumn) in parentColumns.enumerated() {
            outEdges.append(LaneEdge(
                fromColumn: column,
                toColumn: parentColumn,
                color: LanePalette.color(for: commit.parents[index])
            ))
        }

        appendThroughLaneEdges(in: lanes, skipping: parentColumns, into: &inEdges, and: &outEdges)

        return LayoutRow(
            commit: commit,
            column: column,
            inEdges: inEdges,
            outEdges: outEdges,
            refs: []
        )
    }

    /// Pick the column for a commit: leftmost lane already waiting on its
    /// SHA, else the first free slot (creating a new lane if needed).
    /// Clears the chosen lane so the caller can re-use it when placing
    /// parents below.
    private static func claimColumn(for sha: String, in lanes: inout [String?]) -> Int {
        let column: Int = if let expected = lanes.firstIndex(where: { $0 == sha }) {
            expected
        } else {
            firstFreeSlot(in: lanes)
        }
        if column >= lanes.count {
            lanes.append(nil)
        }
        lanes[column] = nil
        return column
    }

    /// Collect — and clear — every OTHER lane waiting on the same SHA. The
    /// commit's own column is already consumed by `claimColumn` and is
    /// returned at the head of the list so edge generation treats it like
    /// any other converging lane.
    private static func consumeConvergingLanes(
        for sha: String,
        column: Int,
        in lanes: inout [String?]
    ) -> [Int] {
        var converging: [Int] = [column]
        for index in lanes.indices where lanes[index] == sha {
            lanes[index] = nil
            converging.append(index)
        }
        return converging
    }

    /// Place each parent into a lane for the row below, applying
    /// first-parent preference.
    ///
    /// Returns the parallel column array index-aligned to `parents`.
    private static func placeParents(
        _ parents: [String],
        commitColumn: Int,
        in lanes: inout [String?]
    ) -> [Int] {
        var columns: [Int] = []
        columns.reserveCapacity(parents.count)
        for (index, parent) in parents.enumerated() {
            columns.append(placeOneParent(parent, parentIndex: index, commitColumn: commitColumn, in: &lanes))
        }
        return columns
    }

    /// Place a single parent. Joins an existing waiting lane if one exists
    /// (diamonds / shared ancestry); else keeps the commit's own column for
    /// the first parent, or grabs the leftmost free slot for secondary
    /// parents (merge, octopus).
    private static func placeOneParent(
        _ parent: String,
        parentIndex: Int,
        commitColumn: Int,
        in lanes: inout [String?]
    ) -> Int {
        if let existing = lanes.firstIndex(where: { $0 == parent }) {
            return existing
        }
        if parentIndex == 0 {
            lanes[commitColumn] = parent
            return commitColumn
        }
        let slot = firstFreeSlot(in: lanes)
        if slot >= lanes.count {
            lanes.append(parent)
        } else {
            lanes[slot] = parent
        }
        return slot
    }

    /// Emit a top↔bottom vertical edge pair for every lane that is still
    /// occupied but was NOT touched by this row's commit or parent
    /// placement — those are the branches passing by behind the commit dot.
    private static func appendThroughLaneEdges(
        in lanes: [String?],
        skipping parentColumns: [Int],
        into inEdges: inout [LaneEdge],
        and outEdges: inout [LaneEdge]
    ) {
        let skip = Set(parentColumns)
        for index in lanes.indices {
            guard let waitingSha = lanes[index], !skip.contains(index) else { continue }
            let color = LanePalette.color(for: waitingSha)
            inEdges.append(LaneEdge(fromColumn: index, toColumn: index, color: color))
            outEdges.append(LaneEdge(fromColumn: index, toColumn: index, color: color))
        }
    }

    /// Leftmost nil slot in `lanes`, else `lanes.count` (caller appends).
    private static func firstFreeSlot(in lanes: [String?]) -> Int {
        for index in lanes.indices where lanes[index] == nil {
            return index
        }
        return lanes.count
    }

    /// Drop trailing nils so the lanes vector doesn't grow unbounded across
    /// a long history with transient wide sections.
    private static func trimTrailingNils(_ lanes: inout [String?]) {
        while lanes.last == .some(nil) {
            lanes.removeLast()
        }
    }
}
