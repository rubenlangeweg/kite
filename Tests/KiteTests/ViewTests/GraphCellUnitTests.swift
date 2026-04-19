import SwiftUI
import Testing
@testable import Kite

/// Small unit tests covering the pure geometry and palette-mapping helpers
/// of `GraphCell`. Snapshot coverage for shape-level output lives in
/// `GraphCellSnapshotTests`; these tests exist so a palette or layout math
/// regression fails cheaply without rebuilding a PNG reference.
@Suite("GraphCell unit")
struct GraphCellUnitTests {
    /// Trivial commit builder — matches `GraphLayoutTests.commit`.
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

    @Test("columnX for column 0 sits at laneWidth / 2")
    func columnXForZeroIndex() {
        let row = LayoutRow(commit: Self.commit("A"), column: 0, inEdges: [], outEdges: [], refs: [])
        let cell = GraphCell(row: row, laneCount: 1)
        #expect(cell.columnX(0) == GraphCell.laneWidth / 2)
    }

    @Test("columnX for column N is (N + 0.5) * laneWidth")
    func columnXForN() {
        let row = LayoutRow(commit: Self.commit("A"), column: 0, inEdges: [], outEdges: [], refs: [])
        let cell = GraphCell(row: row, laneCount: 4)
        #expect(cell.columnX(3) == 3.5 * GraphCell.laneWidth)
    }

    @Test("every LaneColor case maps to a non-clear SwiftUI Color")
    func laneColorMappingIsExhaustive() {
        // A switch over `LaneColor` in the `swiftUIColor` mapping already
        // forces exhaustiveness at compile time. This runtime test adds a
        // belt-and-braces check that no case was accidentally mapped to
        // `Color.clear`, which would produce invisible dots / edges.
        for laneColor in LaneColor.allCases {
            #expect(laneColor.swiftUIColor != Color.clear)
        }
    }
}
