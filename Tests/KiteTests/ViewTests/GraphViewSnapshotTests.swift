import AppKit
import Foundation
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Kite

/// Snapshot coverage for `GraphView`'s banner subviews + pure `GraphViewContent`.
///
/// Design rationale per the M4-graph-scroll-container brief:
///   - Full-List snapshots are brittle (List row hosts resize, internal chrome
///     renders differently under NSHostingController). We therefore snapshot
///     the two banner views in isolation, plus `GraphViewContent` driven with
///     an empty rows array (the empty-state path that doesn't hit List).
///   - Row-level snapshot coverage already lives in
///     `GraphRowContentSnapshotTests` (M4-graph-row-meta).
///
/// Each case must produce a distinct md5 — verified per AGENTS.md "snapshot
/// tests must not be byte-identical".
///
/// Fulfills: VAL-GRAPH-011 (shallow banner), truncation marker from
/// VAL-GRAPH-001 (commit-limit footer).
final class GraphViewSnapshotTests: XCTestCase {
    // MARK: - Shallow banner

    @MainActor
    func testShallowBannerLight() {
        let host = Self.host(Self.wrap(ShallowCloneBanner(), size: Self.bannerSize), appearance: .light)
        assertSnapshot(
            of: host,
            as: .image(size: Self.bannerSize),
            named: "GraphView.ShallowBanner.light"
        )
    }

    @MainActor
    func testShallowBannerDark() {
        let host = Self.host(Self.wrap(ShallowCloneBanner(), size: Self.bannerSize), appearance: .dark)
        assertSnapshot(
            of: host,
            as: .image(size: Self.bannerSize),
            named: "GraphView.ShallowBanner.dark"
        )
    }

    // MARK: - Commit-limit footer

    @MainActor
    func testCommitLimitFooterLight() {
        let host = Self.host(Self.wrap(CommitLimitFooter(), size: Self.footerSize), appearance: .light)
        assertSnapshot(
            of: host,
            as: .image(size: Self.footerSize),
            named: "GraphView.CommitLimitFooter.light"
        )
    }

    @MainActor
    func testCommitLimitFooterDark() {
        let host = Self.host(Self.wrap(CommitLimitFooter(), size: Self.footerSize), appearance: .dark)
        assertSnapshot(
            of: host,
            as: .image(size: Self.footerSize),
            named: "GraphView.CommitLimitFooter.dark"
        )
    }

    // MARK: - Empty GraphViewContent (no rows, no shallow, no error)

    @MainActor
    func testEmptyGraphViewContent() {
        let content = GraphViewContent(rows: [])
        let host = Self.host(
            Self.wrap(content, size: Self.contentSize),
            appearance: .light
        )
        assertSnapshot(
            of: host,
            as: .image(size: Self.contentSize),
            named: "GraphViewContent.Empty.light"
        )
    }

    // MARK: - Helpers

    private static let bannerSize = CGSize(width: 360, height: 28)
    private static let footerSize = CGSize(width: 360, height: 28)
    private static let contentSize = CGSize(width: 360, height: 220)

    @MainActor
    private static func wrap(_ view: some View, size: CGSize) -> some View {
        view
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
        host.view.appearance = appearance.appearance
        return host
    }
}
