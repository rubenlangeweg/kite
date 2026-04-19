import AppKit
import Foundation
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Kite

/// Snapshot coverage for the `StatusHeaderContent` presentational subview
/// (VAL-BRANCH-005, plus VAL-UI-010 dark-mode parity sanity check).
///
/// Each case drives a distinct visual branch of the header:
///   - clean working tree (green check + "Clean").
///   - dirty tree (mixed staged + modified pills).
///   - detached HEAD label.
///   - upstream divergence (↑3 ↓2 indicator) on top of a dirty tree.
///   - dark-mode parity for the dirty case.
///
/// Per AGENTS.md "Established patterns": the hosted views force the
/// `NSHostingController`'s appearance to either `.aqua` (light) or
/// `.darkAqua` (dark) so `NSColor.windowBackgroundColor`/
/// `NSColor.controlBackgroundColor` actually resolve to distinct bytes across
/// appearances. `preferredColorScheme` alone doesn't propagate through
/// `NSColor`-based backgrounds.
final class StatusHeaderSnapshotTests: XCTestCase {
    private static let size = CGSize(width: 360, height: 36)

    // MARK: - Case: clean working tree

    @MainActor
    func testClean() {
        let summary = StatusSummary(
            branch: "main", detachedAt: nil, upstream: "origin/main",
            ahead: 0, behind: 0, staged: 0, modified: 0, untracked: 0
        )
        let host = Self.host(Self.wrap(summary: summary), appearance: .light)
        assertSnapshot(
            of: host,
            as: .image(size: Self.size),
            named: "StatusHeader.Clean.light"
        )
    }

    // MARK: - Case: staged + modified (dirty)

    @MainActor
    func testStagedAndModified() {
        let summary = StatusSummary(
            branch: "main", detachedAt: nil, upstream: nil,
            ahead: 0, behind: 0, staged: 2, modified: 3, untracked: 0
        )
        let host = Self.host(Self.wrap(summary: summary), appearance: .light)
        assertSnapshot(
            of: host,
            as: .image(size: Self.size),
            named: "StatusHeader.StagedAndModified.light"
        )
    }

    // MARK: - Case: detached HEAD

    @MainActor
    func testDetachedHead() {
        let summary = StatusSummary(
            branch: nil, detachedAt: "abc1234", upstream: nil,
            ahead: 0, behind: 0, staged: 0, modified: 0, untracked: 0
        )
        let host = Self.host(Self.wrap(summary: summary), appearance: .light)
        assertSnapshot(
            of: host,
            as: .image(size: Self.size),
            named: "StatusHeader.DetachedHead.light"
        )
    }

    // MARK: - Case: ahead/behind indicator

    @MainActor
    func testWithAheadBehind() {
        // Drive both the ahead/behind cluster AND a non-zero pill so the
        // snapshot captures the full "busy branch" shape.
        let summary = StatusSummary(
            branch: "main", detachedAt: nil, upstream: "origin/main",
            ahead: 3, behind: 2, staged: 0, modified: 1, untracked: 0
        )
        let host = Self.host(Self.wrap(summary: summary), appearance: .light)
        assertSnapshot(
            of: host,
            as: .image(size: Self.size),
            named: "StatusHeader.WithAheadBehind.light"
        )
    }

    // MARK: - Dark mode parity

    @MainActor
    func testDarkMode() {
        let summary = StatusSummary(
            branch: "main", detachedAt: nil, upstream: nil,
            ahead: 0, behind: 0, staged: 2, modified: 3, untracked: 0
        )
        let host = Self.host(Self.wrap(summary: summary), appearance: .dark)
        assertSnapshot(
            of: host,
            as: .image(size: Self.size),
            named: "StatusHeader.StagedAndModified.dark"
        )
    }

    // MARK: - Helpers

    /// Wrap `StatusHeaderContent` in a fixed-size frame so the snapshot is
    /// deterministic regardless of content width.
    @MainActor
    private static func wrap(summary: StatusSummary?) -> some View {
        StatusHeaderContent(summary: summary)
            .frame(width: size.width, height: size.height)
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
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.appearance = appearance.appearance
        return host
    }
}
