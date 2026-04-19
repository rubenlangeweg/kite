import AppKit
import Foundation
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Kite

/// Snapshot coverage for `GraphRowContent` — the composed graph-cell + pill
/// cluster + subject + author + relative-age row.
///
/// Per AGENTS.md "Established patterns":
///   - Each case must produce a distinct md5 (verify with
///     `find __Snapshots__/GraphRowContentSnapshotTests -name '*.png'
///       -exec md5 -r {} \; | sort -u | wc -l`).
///   - `NSHostingController.view.appearance` is set explicitly so dark/light
///     parity tests actually reflect `NSColor.controlBackgroundColor` —
///     `.preferredColorScheme` alone doesn't propagate to `NSColor`-backed
///     backgrounds.
///   - Content is wrapped in a `Color(nsColor: .windowBackgroundColor)`
///     background so the appearance swap renders distinct bytes across modes.
///
/// Relative-age determinism trick: the row uses `TimelineView` which reads
/// `Date()` at render time. To keep snapshots deterministic across test runs,
/// commits are stamped at `Date(timeIntervalSince1970: 0)` — the formatter
/// will render them as a large number of years, which stays stable across any
/// single run and between runs (a one-year rollover test-suite drift is the
/// only way this could change, and that's a sensible failure mode).
final class GraphRowContentSnapshotTests: XCTestCase {
    private static let epoch = Date(timeIntervalSince1970: 0)
    private static let rowWidth: CGFloat = 600

    // MARK: - Commit / row builders

    private static func commit(sha: String = "abc123", subject: String = "add login screen", author: String = "Ruben") -> Commit {
        Commit(
            sha: sha,
            parents: ["parent"],
            authorName: author,
            authorEmail: "test@kite.local",
            authoredAt: epoch,
            subject: subject
        )
    }

    private static func row(_ commit: Commit, column: Int = 0, refs: [RefKind] = []) -> LayoutRow {
        LayoutRow(
            commit: commit,
            column: column,
            inEdges: [LaneEdge(fromColumn: 0, toColumn: 0, color: .blue)],
            outEdges: [LaneEdge(fromColumn: 0, toColumn: 0, color: .blue)],
            refs: refs
        )
    }

    // MARK: - 1. Single row, no refs

    @MainActor
    func testSingleRow() {
        let row = Self.row(Self.commit(subject: "Linear commit on mainline"))
        let host = Self.host(Self.wrap(row: row, laneCount: 1), appearance: .light)
        assertSnapshot(
            of: host,
            as: .image(size: Self.size()),
            named: "GraphRowContent.SingleRow.light"
        )
    }

    // MARK: - 2. Single local branch pill

    @MainActor
    func testWithSingleLocalBranch() {
        let row = Self.row(
            Self.commit(subject: "feat: add OAuth provider"),
            refs: [.localBranch("main")]
        )
        let host = Self.host(Self.wrap(row: row, laneCount: 1), appearance: .light)
        assertSnapshot(
            of: host,
            as: .image(size: Self.size()),
            named: "GraphRowContent.WithSingleLocalBranch.light"
        )
    }

    // MARK: - 3. Local + remote branches side-by-side

    @MainActor
    func testWithLocalAndRemote() {
        let row = Self.row(
            Self.commit(subject: "chore: bump version to 0.2.0"),
            refs: [
                .localBranch("main"),
                .remoteBranch(remote: "origin", branch: "main")
            ]
        )
        let host = Self.host(Self.wrap(row: row, laneCount: 1), appearance: .light)
        assertSnapshot(
            of: host,
            as: .image(size: Self.size()),
            named: "GraphRowContent.WithLocalAndRemote.light"
        )
    }

    // MARK: - 4. Overflow — 5 refs → 3 visible + "+2"

    @MainActor
    func testWithOverflow() {
        // Five distinct refs: three visible + "+2" label per VAL-GRAPH-007.
        let row = Self.row(
            Self.commit(subject: "merge: release train for 2026-Q2"),
            refs: [
                .localBranch("main"),
                .remoteBranch(remote: "origin", branch: "main"),
                .remoteBranch(remote: "upstream", branch: "main"),
                .localBranch("release-2026-q2"),
                .remoteBranch(remote: "origin", branch: "release-2026-q2")
            ]
        )
        let host = Self.host(Self.wrap(row: row, laneCount: 1), appearance: .light)
        assertSnapshot(
            of: host,
            as: .image(size: Self.size()),
            named: "GraphRowContent.WithOverflow.light"
        )
    }

    // MARK: - 5. HEAD pill next to local branch

    @MainActor
    func testHEADPill() {
        // `GraphRowRefs.enrich` is responsible for prepending .head; here we
        // hand-feed the result so the snapshot exercises the RefPill rendering
        // path for all three rendered styles in one frame.
        let row = Self.row(
            Self.commit(subject: "ship: HEAD marker rendering"),
            refs: [
                .head,
                .localBranch("main"),
                .remoteBranch(remote: "origin", branch: "main")
            ]
        )
        let host = Self.host(Self.wrap(row: row, laneCount: 1), appearance: .light)
        assertSnapshot(
            of: host,
            as: .image(size: Self.size()),
            named: "GraphRowContent.HEADPill.light"
        )
    }

    // MARK: - 6. Long subject truncates (tail)

    @MainActor
    func testLongSubjectTruncates() {
        let longSubject = String(
            repeating: "very long commit subject that will absolutely not fit inside a single line of a 600-point row ",
            count: 2
        )
        let row = Self.row(Self.commit(subject: longSubject))
        let host = Self.host(Self.wrap(row: row, laneCount: 1), appearance: .light)
        assertSnapshot(
            of: host,
            as: .image(size: Self.size()),
            named: "GraphRowContent.LongSubjectTruncates.light"
        )
    }

    // MARK: - 7. Selected row

    @MainActor
    func testSelected() {
        let row = Self.row(
            Self.commit(subject: "selected for diff pane"),
            refs: [.localBranch("main")]
        )
        let host = Self.host(Self.wrap(row: row, laneCount: 1, isSelected: true), appearance: .light)
        assertSnapshot(
            of: host,
            as: .image(size: Self.size()),
            named: "GraphRowContent.Selected.light"
        )
    }

    // MARK: - 8. Dark-mode parity — repeat `WithLocalAndRemote` under dark aqua

    @MainActor
    func testDarkMode() {
        let row = Self.row(
            Self.commit(subject: "chore: bump version to 0.2.0"),
            refs: [
                .localBranch("main"),
                .remoteBranch(remote: "origin", branch: "main")
            ]
        )
        let host = Self.host(Self.wrap(row: row, laneCount: 1), appearance: .dark)
        assertSnapshot(
            of: host,
            as: .image(size: Self.size()),
            named: "GraphRowContent.WithLocalAndRemote.dark"
        )
    }

    // MARK: - Helpers

    private static func size() -> CGSize {
        CGSize(width: rowWidth, height: GraphCell.rowHeight)
    }

    @MainActor
    private static func wrap(row: LayoutRow, laneCount: Int, isSelected: Bool = false) -> some View {
        GraphRowContent(row: row, laneCount: laneCount, isSelected: isSelected)
            .frame(width: rowWidth, height: GraphCell.rowHeight)
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
        appearance: HostAppearance
    ) -> NSHostingController<V> {
        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(origin: .zero, size: size())
        host.view.appearance = appearance.appearance
        return host
    }
}
