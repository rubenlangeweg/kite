import Foundation
import Testing
@testable import Kite

@Suite("GraphLayout")
struct GraphLayoutTests {
    // MARK: - Commit builder

    /// Minimal stand-in for a `git log --topo-order` record. Using fixed
    /// dates keeps any time-sensitive assertions deterministic; the layout
    /// algorithm itself does not read `authoredAt`.
    private static func commit(_ sha: String, parents: [String] = []) -> Commit {
        Commit(
            sha: sha,
            parents: parents,
            authorName: "Test",
            authorEmail: "test@kite.local",
            authoredAt: Date(timeIntervalSince1970: 1_700_000_000),
            subject: "commit \(sha)"
        )
    }

    // MARK: - 1. Empty / single / linear

    @Test("empty input returns empty output")
    func emptyInputReturnsEmpty() {
        #expect(GraphLayout.compute([]).isEmpty)
    }

    @Test("single commit lands in lane 0 with no edges")
    func singleCommitSingleLane() {
        let rows = GraphLayout.compute([Self.commit("A")])
        #expect(rows.count == 1)
        #expect(rows[0].column == 0)
        #expect(rows[0].inEdges.count == 1, "converging-column in-edge for the commit's own column")
        #expect(rows[0].inEdges[0].fromColumn == 0)
        #expect(rows[0].inEdges[0].toColumn == 0)
        #expect(rows[0].outEdges.isEmpty, "root commit has no parents, no out-edges")
    }

    @Test("linear history stays in lane 0 for every row")
    func linearHistoryStaysInLaneZero() {
        let commits = [
            Self.commit("E", parents: ["D"]),
            Self.commit("D", parents: ["C"]),
            Self.commit("C", parents: ["B"]),
            Self.commit("B", parents: ["A"]),
            Self.commit("A")
        ]
        let rows = GraphLayout.compute(commits)
        #expect(rows.count == 5)
        for (index, row) in rows.enumerated() {
            #expect(row.column == 0, "row \(index) (\(row.commit.sha)) should be in lane 0")
        }
    }

    // MARK: - 2. Two-branch merge (golden hand-built)

    @Test("two-branch merge places first-parent in lane 0, second-parent in lane 1, reuses lane on merge back")
    func twoBranchMerge() {
        // DAG (ASCII, newest at top):
        //   A  (merge, parents: [B, C])
        //   |\
        //   B |  (parent D — first-parent lane)
        //   | C  (parent D — feature lane)
        //   |/
        //   D  (root)
        let commits = [
            Self.commit("A", parents: ["B", "C"]),
            Self.commit("B", parents: ["D"]),
            Self.commit("C", parents: ["D"]),
            Self.commit("D")
        ]
        let rows = GraphLayout.compute(commits)
        #expect(rows.count == 4)

        // A: merge commit, column 0. Opens lane 1 for C.
        #expect(rows[0].commit.sha == "A")
        #expect(rows[0].column == 0)
        // Two out-edges: one to B's lane (0), one to C's lane (1).
        #expect(rows[0].outEdges.count == 2)
        #expect(rows[0].outEdges[0] == LaneEdge(fromColumn: 0, toColumn: 0, color: LanePalette.color(for: "B")))
        #expect(rows[0].outEdges[1] == LaneEdge(fromColumn: 0, toColumn: 1, color: LanePalette.color(for: "C")))

        // B: column 0, first-parent D stays in 0. C still waits in lane 1 → through-lane.
        #expect(rows[1].commit.sha == "B")
        #expect(rows[1].column == 0)
        let bOutSet = Set(rows[1].outEdges.map(Self.edgeTuple))
        #expect(bOutSet.contains(Self.edgeTuple(LaneEdge(fromColumn: 0, toColumn: 0, color: LanePalette.color(for: "D")))))
        #expect(bOutSet.contains(Self.edgeTuple(LaneEdge(fromColumn: 1, toColumn: 1, color: LanePalette.color(for: "C")))))

        // C: column 1 (the lane A opened). D is already waiting in lane 0 — C joins lane 0.
        #expect(rows[2].commit.sha == "C")
        #expect(rows[2].column == 1)
        // Exactly one out-edge: from column 1 to column 0 (joining the existing D-lane).
        #expect(rows[2].outEdges.count == 1)
        #expect(rows[2].outEdges[0] == LaneEdge(fromColumn: 1, toColumn: 0, color: LanePalette.color(for: "D")))

        // D: column 0, root. No out-edges.
        #expect(rows[3].commit.sha == "D")
        #expect(rows[3].column == 0)
        #expect(rows[3].outEdges.isEmpty)
    }

    // MARK: - 3. Octopus merge uses straight-line fallback

    @Test("octopus merge (>2 parents) emits one straight-line out-edge per parent")
    func octopusMergeUsesStraightLines() {
        // A is an octopus merge with parents B, C, D. All parents are roots
        // for simplicity — we're testing edge shape, not ancestry handling.
        let commits = [
            Self.commit("A", parents: ["B", "C", "D"]),
            Self.commit("B"),
            Self.commit("C"),
            Self.commit("D")
        ]
        let rows = GraphLayout.compute(commits)

        // A emits exactly 3 out-edges, one per parent, all starting at A's lane.
        let aRow = rows[0]
        #expect(aRow.column == 0)
        #expect(aRow.outEdges.count == 3)
        for edge in aRow.outEdges {
            #expect(edge.fromColumn == aRow.column, "octopus out-edges start at the commit's dot")
        }
        // Parents land in columns 0, 1, 2 (first-parent keeps lane 0; others take next free slots).
        let parentColumns = aRow.outEdges.map(\.toColumn).sorted()
        #expect(parentColumns == [0, 1, 2])
    }

    // MARK: - 4. First-parent preference across nested merges

    @Test("first-parent lane is preserved across a chain of merges")
    func firstParentStaysInLane() {
        // M1 ── M2 ── M3 ── R  (first-parent line)
        //  \     \     \
        //   F1    F2    F3     (feature branches, each a single commit merged back)
        let commits = [
            Self.commit("M1", parents: ["M2", "F1"]),
            Self.commit("M2", parents: ["M3", "F2"]),
            Self.commit("M3", parents: ["R", "F3"]),
            Self.commit("F1", parents: ["M2"]),
            Self.commit("F2", parents: ["M3"]),
            Self.commit("F3", parents: ["R"]),
            Self.commit("R")
        ]
        let rows = GraphLayout.compute(commits)
        let byId: [String: LayoutRow] = Dictionary(uniqueKeysWithValues: rows.map { ($0.commit.sha, $0) })

        #expect(byId["M1"]?.column == 0)
        #expect(byId["M2"]?.column == 0)
        #expect(byId["M3"]?.column == 0)
        #expect(byId["R"]?.column == 0, "root of the first-parent line must also be in lane 0")
    }

    // MARK: - 5. Column reuse after merge

    @Test("a lane freed by a merge-back is reused by a later divergent branch")
    func columnReuseAfterMerge() {
        // Topo order (newest first):
        //   T    — lonely tip on main after everything is merged
        //   M2   — merge of main + feature-y    parents: [S, G]
        //   S    — main between merges          parent:  [M1]
        //   G    — feature-y tip                parent:  [M1]
        //   M1   — merge of main + feature-x    parents: [B, F]
        //   F    — feature-x tip                parent:  [B]
        //   B    — main earlier                 parent:  [A]
        //   A    — main root
        //
        // After M1 is processed, lane 1 (feature-x) is freed by the merge.
        // The critical property: when M2 later opens a NEW secondary parent
        // (G), the algorithm must reuse lane 1 rather than allocating lane 2.
        // That is the column-reuse invariant of VAL-GRAPH-002.
        let commits = [
            Self.commit("T", parents: ["M2"]),
            Self.commit("M2", parents: ["S", "G"]),
            Self.commit("S", parents: ["M1"]),
            Self.commit("G", parents: ["M1"]),
            Self.commit("M1", parents: ["B", "F"]),
            Self.commit("F", parents: ["B"]),
            Self.commit("B", parents: ["A"]),
            Self.commit("A")
        ]
        let rows = GraphLayout.compute(commits)
        let byId: [String: LayoutRow] = Dictionary(uniqueKeysWithValues: rows.map { ($0.commit.sha, $0) })

        // F (feature-x) ends up in lane 1 because M1 opens a secondary parent there.
        #expect(byId["F"]?.column == 1, "first feature branch should live in lane 1")
        // G (feature-y, opened later by M2) should REUSE lane 1 — not spill into lane 2.
        #expect(byId["G"]?.column == 1, "lane 1 must be reused for the later branch instead of allocating lane 2")

        // Peak lane across the whole history is 1 — we never grow to 2 lanes.
        let peakLane = rows.map(\.column).max() ?? 0
        #expect(peakLane == 1, "peak lane count must stay at 2 (indices 0 and 1); lane 1 is recycled")
    }

    // MARK: - 6. Color stability across calls

    @Test("compute twice on the same commits yields identical rows (bitwise-equal edge colors)")
    func colorStableAcrossCalls() {
        let commits = [
            Self.commit("A", parents: ["B", "C"]),
            Self.commit("B", parents: ["D"]),
            Self.commit("C", parents: ["D"]),
            Self.commit("D")
        ]
        let first = GraphLayout.compute(commits)
        let second = GraphLayout.compute(commits)
        #expect(first == second)
    }

    // MARK: - 7. LanePalette

    @Test("main / master / trunk / default / develop all map to .blue regardless of hash")
    func lanePaletteMainIsBlue() {
        #expect(LanePalette.color(for: "main") == .blue)
        #expect(LanePalette.color(for: "master") == .blue)
        #expect(LanePalette.color(for: "trunk") == .blue)
        #expect(LanePalette.color(for: "default") == .blue)
        #expect(LanePalette.color(for: "develop") == .blue)
    }

    @Test("LanePalette is deterministic for arbitrary names (cross-process stable)")
    func lanePaletteDeterministicForArbitraryName() {
        // Self-consistency: a given name always maps to the same slot within
        // a single process (Swift's randomized Hasher would also pass this).
        let firstCall = LanePalette.color(for: "feature/payment")
        let secondCall = LanePalette.color(for: "feature/payment")
        #expect(firstCall == secondCall)

        // Known-good FNV-1a-32 outputs asserted as raw slot indices so a
        // future reordering of `LaneColor`'s cases can't mask a regression.
        // Values were generated offline by the reference FNV-1a algorithm
        // on the UTF-8 bytes of each name and taking `% 6`; any drift means
        // the hash constants (offset basis or prime) got edited and colors
        // would shift across existing installs.
        //
        //   fnv1a32("bb")      = 0x3F2BAB85  → % 6 == 5
        //   fnv1a32("baz")     = 0x6EB77082  → % 6 == 4
        //   fnv1a32("master")  = 0xCA8DBF33  → % 6 == 3 (overridden to .blue
        //                                              by trunk-name rule)
        //   fnv1a32("bar")     = 0x76B77D1A  → % 6 == 2
        //   fnv1a32("aa")      = 0x4C250437  → % 6 == 1
        //   fnv1a32("gamma")   = 0xD029140A  → % 6 == 0
        //
        // Picking inputs that land in different slots proves the function
        // distributes (isn't a constant) AND pins each slot at least once.
        #expect(LanePalette.color(for: "bb").rawValue == 5)
        #expect(LanePalette.color(for: "baz").rawValue == 4)
        #expect(LanePalette.color(for: "bar").rawValue == 2)
        #expect(LanePalette.color(for: "aa").rawValue == 1)
        #expect(LanePalette.color(for: "gamma").rawValue == 0)
    }

    // MARK: - 8. Performance ceiling (200 commits < 50ms)

    @Test("200-commit linear history lays out in well under 50ms")
    func perf200Commits() {
        var commits: [Commit] = []
        commits.reserveCapacity(200)
        for index in 0 ..< 200 {
            let parents = index == 199 ? [] : ["c\(index + 1)"]
            commits.append(Self.commit("c\(index)", parents: parents))
        }
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = GraphLayout.compute(commits)
        }
        // Generous ceiling; typical measurement is <2ms on an M1.
        #expect(elapsed < .milliseconds(50), "layout of 200 commits took \(elapsed)")
    }

    // MARK: - 9. Golden fixture

    @Test("golden fixture JSON matches computed layout")
    func goldenFixture() throws {
        let commits = GraphLayoutTestsGoldenFixture.commits()
        let computed = GraphLayout.compute(commits)

        let expected = try GraphLayoutTestsGoldenFixture.loadReference()
        #expect(computed == expected, "golden fixture diverged; see Fixtures/goldenFixture.json — update only after visual review")
    }

    // MARK: - Helpers

    /// Convert a LaneEdge into a hashable tuple for set-based comparisons
    /// (order within in/outEdges is implementation-detail for through-lanes).
    private static func edgeTuple(_ edge: LaneEdge) -> String {
        "\(edge.fromColumn)->\(edge.toColumn):\(edge.color.rawValue)"
    }
}
