import Foundation

/// One row of the rendered commit-graph DAG — a commit pinned to a lane
/// (column) with the edges feeding into and out of its dot.
///
/// `inEdges` describe the line segments converging from the row above onto
/// this row's dot. `outEdges` describe the segments diverging from this row's
/// dot down to the row below. A plain vertical through-lane (a branch passing
/// by with no commit on this row) is represented as an edge pair with
/// `fromColumn == toColumn` present in BOTH `inEdges` and `outEdges` at that
/// column — the consumer renderer draws it as a single straight line.
///
/// `refs` is always empty in the M4-graph-layout pass; it is populated by
/// M4-graph-row-meta, which owns commit→ref resolution.
///
/// `id == commit.sha` makes the row usable directly in SwiftUI's `List`
/// without a secondary ID source.
struct LayoutRow: Equatable, Identifiable, Codable {
    let commit: Commit
    let column: Int
    let inEdges: [LaneEdge]
    let outEdges: [LaneEdge]
    let refs: [RefKind]

    var id: String {
        commit.sha
    }
}

/// A single edge segment spanning half a row — either from the row above
/// down to this row's dot (in-edge) or from this row's dot down to the row
/// below (out-edge). `fromColumn` is the x-position at the top of the edge's
/// vertical range, `toColumn` the x-position at the bottom.
///
/// Color is carried on the edge rather than looked up at render time so the
/// renderer stays a pure function of `[LayoutRow]`.
struct LaneEdge: Equatable, Codable {
    let fromColumn: Int
    let toColumn: Int
    let color: LaneColor
}
