import AppKit
import Foundation
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Kite

/// Snapshot coverage for `GraphCell`'s Canvas output across canonical DAG
/// shapes and both appearance modes. Each case is designed to produce a
/// distinct md5 against every other — verified with
/// `md5 ... | sort -u | wc -l` after recording.
///
/// Per AGENTS.md "Established patterns":
///   - `NSHostingController.view.appearance` is set explicitly rather than
///     relying on `.preferredColorScheme`, because Dark Aqua color resolution
///     for `NSColor.windowBackgroundColor` only kicks in via the hosting
///     controller's `appearance`.
///   - Content is wrapped in a `Color(nsColor: .windowBackgroundColor)`
///     background so the appearance swap actually produces different bytes.
///   - Inner `GraphCell` is exercised directly — no environment, no view
///     model.
final class GraphCellSnapshotTests: XCTestCase {
    // MARK: - Commit / row builders

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

    // MARK: - Case: single dot, no edges

    @MainActor
    func testSingleDotNoEdges() {
        // Hand-built to isolate the "no edges at all" case — `GraphLayout`
        // always emits a converging in-edge at the commit's own column, so
        // going through it wouldn't exercise the truly-empty-edges branch.
        let row = LayoutRow(
            commit: Self.commit("A"),
            column: 0,
            inEdges: [],
            outEdges: [],
            refs: []
        )
        let host = Self.host(Self.wrap(cell: GraphCell(row: row, laneCount: 1)), laneCount: 1)
        assertSnapshot(
            of: host,
            as: .image(size: Self.size(laneCount: 1)),
            named: "GraphCell.SingleDotNoEdges.light"
        )
    }

    // MARK: - Case: linear history — first, middle, last (stacked)

    @MainActor
    func testLinearThreeRowsFirstMiddleLast() {
        // Three commits, newest first. Produces three rows all in lane 0:
        //   - row 0 (C): no in-edges, out-edge to parent B.
        //   - row 1 (B): in-edge from C above, out-edge to parent A.
        //   - row 2 (A): in-edge from B above, no out-edges (root).
        let rows = GraphLayout.compute([
            Self.commit("C", parents: ["B"]),
            Self.commit("B", parents: ["A"]),
            Self.commit("A")
        ])
        let stack = VStack(spacing: 0) {
            ForEach(rows) { row in
                GraphCell(row: row, laneCount: 1)
            }
        }
        let host = Self.host(Self.wrap(stack, laneCount: 1, rowCount: rows.count), laneCount: 1, rowCount: rows.count)
        assertSnapshot(
            of: host,
            as: .image(size: Self.size(laneCount: 1, rowCount: rows.count)),
            named: "GraphCell.LinearThreeRows.light"
        )
    }

    // MARK: - Case: merge inbound — diagonal in-edges converging on column 0

    @MainActor
    func testMergeInbound() {
        // Commit M has two parents P1 (mainline) and P2 (feature-branch),
        // with a diverged feature branch above M. Running `GraphLayout` on
        // the sequence below yields the merge row with:
        //   - column 0
        //   - in-edges from columns 0 and 1 (the feature branch converging)
        //   - out-edges to both parents (first-parent stays in col 0,
        //     second-parent opens col 1 below the merge).
        let rows = GraphLayout.compute([
            Self.commit("M", parents: ["P1", "P2"]),
            Self.commit("F", parents: ["P2"]),
            Self.commit("P1", parents: ["R"]),
            Self.commit("P2", parents: ["R"]),
            Self.commit("R")
        ])
        // Snapshot just the merge row itself so the diagonal in-edges are
        // the salient detail.
        let merge = rows[0]
        let laneCount = 2
        let host = Self.host(Self.wrap(cell: GraphCell(row: merge, laneCount: laneCount)), laneCount: laneCount)
        assertSnapshot(
            of: host,
            as: .image(size: Self.size(laneCount: laneCount)),
            named: "GraphCell.MergeInbound.light"
        )
    }

    // MARK: - Case: branch outbound — one in-edge, two out-edges (fork)

    @MainActor
    func testBranchOutbound() {
        // A single commit at column 0 whose outgoing edges fork into column
        // 0 (first parent straight down) and column 1 (second parent
        // diagonal). Hand-built because `GraphLayout` produces a fork only
        // on merge commits; we want a pure branch-off shape here.
        let row = LayoutRow(
            commit: Self.commit("X", parents: ["P1", "P2"]),
            column: 0,
            inEdges: [
                LaneEdge(fromColumn: 0, toColumn: 0, color: .blue)
            ],
            outEdges: [
                LaneEdge(fromColumn: 0, toColumn: 0, color: .blue),
                LaneEdge(fromColumn: 0, toColumn: 1, color: .orange)
            ],
            refs: []
        )
        let laneCount = 2
        let host = Self.host(Self.wrap(cell: GraphCell(row: row, laneCount: laneCount)), laneCount: laneCount)
        assertSnapshot(
            of: host,
            as: .image(size: Self.size(laneCount: laneCount)),
            named: "GraphCell.BranchOutbound.light"
        )
    }

    // MARK: - Case: octopus merge — 3 in-edges converging on column 0

    @MainActor
    func testOctopusMerge() {
        // Three feature branches merge into `main` at once (library §2's
        // straight-line fallback). Hand-built for shape control.
        let row = LayoutRow(
            commit: Self.commit("O", parents: ["A", "B", "C"]),
            column: 0,
            inEdges: [
                LaneEdge(fromColumn: 0, toColumn: 0, color: .blue),
                LaneEdge(fromColumn: 1, toColumn: 0, color: .orange),
                LaneEdge(fromColumn: 2, toColumn: 0, color: .green)
            ],
            outEdges: [
                LaneEdge(fromColumn: 0, toColumn: 0, color: .blue)
            ],
            refs: []
        )
        let laneCount = 3
        let host = Self.host(Self.wrap(cell: GraphCell(row: row, laneCount: laneCount)), laneCount: laneCount)
        assertSnapshot(
            of: host,
            as: .image(size: Self.size(laneCount: laneCount)),
            named: "GraphCell.OctopusMerge.light"
        )
    }

    // MARK: - Case: current-branch dot — hasRef draws a bolder dot

    @MainActor
    func testCurrentBranchDot() {
        // Same shape as the linear middle row but with `hasRef: true` so
        // the dot radius bumps by 1pt. md5 MUST differ from any case
        // without hasRef.
        let row = LayoutRow(
            commit: Self.commit("HEAD", parents: ["P"]),
            column: 0,
            inEdges: [LaneEdge(fromColumn: 0, toColumn: 0, color: .blue)],
            outEdges: [LaneEdge(fromColumn: 0, toColumn: 0, color: .blue)],
            refs: []
        )
        let cell = GraphCell(row: row, laneCount: 1, hasRef: true)
        let host = Self.host(Self.wrap(cell: cell), laneCount: 1)
        assertSnapshot(
            of: host,
            as: .image(size: Self.size(laneCount: 1)),
            named: "GraphCell.CurrentBranchDot.light"
        )
    }

    // MARK: - Case: selection ring

    @MainActor
    func testSelectionRing() {
        let row = LayoutRow(
            commit: Self.commit("S", parents: ["P"]),
            column: 0,
            inEdges: [LaneEdge(fromColumn: 0, toColumn: 0, color: .blue)],
            outEdges: [LaneEdge(fromColumn: 0, toColumn: 0, color: .blue)],
            refs: []
        )
        let cell = GraphCell(row: row, laneCount: 1, isSelected: true)
        let host = Self.host(Self.wrap(cell: cell), laneCount: 1)
        assertSnapshot(
            of: host,
            as: .image(size: Self.size(laneCount: 1)),
            named: "GraphCell.SelectionRing.light"
        )
    }

    // MARK: - Case: dark-mode parity

    @MainActor
    func testDarkMode() {
        // Repeat the merge-inbound case in Dark Aqua. Bytes must differ
        // from the light version — if they match, the background didn't
        // carry the appearance through and the dark test is a false green.
        let rows = GraphLayout.compute([
            Self.commit("M", parents: ["P1", "P2"]),
            Self.commit("F", parents: ["P2"]),
            Self.commit("P1", parents: ["R"]),
            Self.commit("P2", parents: ["R"]),
            Self.commit("R")
        ])
        let merge = rows[0]
        let laneCount = 2
        let host = Self.host(
            Self.wrap(cell: GraphCell(row: merge, laneCount: laneCount)),
            laneCount: laneCount,
            appearance: .dark
        )
        assertSnapshot(
            of: host,
            as: .image(size: Self.size(laneCount: laneCount)),
            named: "GraphCell.MergeInbound.dark"
        )
    }

    // MARK: - Helpers

    private static func size(laneCount: Int, rowCount: Int = 1) -> CGSize {
        CGSize(
            width: CGFloat(max(laneCount, 1)) * GraphCell.laneWidth,
            height: CGFloat(max(rowCount, 1)) * GraphCell.rowHeight
        )
    }

    /// Wrap a single `GraphCell` in a fixed-size frame + window-background
    /// Color so hosting appearance actually paints differently in Dark vs
    /// Light.
    @MainActor
    private static func wrap(cell: GraphCell) -> some View {
        let sz = size(laneCount: cell.laneCount)
        return cell
            .frame(width: sz.width, height: sz.height)
            .background(Color(nsColor: .windowBackgroundColor))
    }

    @MainActor
    private static func wrap(_ stack: some View, laneCount: Int, rowCount: Int) -> some View {
        let sz = size(laneCount: laneCount, rowCount: rowCount)
        return stack
            .frame(width: sz.width, height: sz.height)
            .background(Color(nsColor: .windowBackgroundColor))
    }

    enum HostAppearance {
        case light
        case dark

        var appearance: NSAppearance {
            switch self {
            case .light:
                // swiftlint:disable:next force_unwrapping
                NSAppearance(named: .aqua)!
            case .dark:
                // swiftlint:disable:next force_unwrapping
                NSAppearance(named: .darkAqua)!
            }
        }
    }

    @MainActor
    private static func host<V: View>(
        _ view: V,
        laneCount: Int,
        rowCount: Int = 1,
        appearance: HostAppearance = .light
    ) -> NSHostingController<V> {
        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(origin: .zero, size: size(laneCount: laneCount, rowCount: rowCount))
        host.view.appearance = appearance.appearance
        return host
    }
}
