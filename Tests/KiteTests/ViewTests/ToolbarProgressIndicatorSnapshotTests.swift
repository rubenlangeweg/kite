import AppKit
import Foundation
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Kite

/// Snapshot coverage for `ToolbarProgressIndicator`'s three visual states:
///   - idle (no active op → zero-width render)
///   - indeterminate (first active item has nil percent)
///   - determinate (first active item has percent set)
///
/// Inner view observes `ProgressCenter` via `@Environment`; we build a
/// fresh center per case and inject it. Per AGENTS.md: wrap in
/// `Color(nsColor: .windowBackgroundColor)` and set the hosting appearance
/// explicitly for stable md5 diffs.
final class ToolbarProgressIndicatorSnapshotTests: XCTestCase {
    // MARK: - Fixed-size containers

    private static let size = CGSize(width: 160, height: 28)

    // MARK: - Cases

    @MainActor
    func testIdle() {
        let center = ProgressCenter()
        let host = Self.host(Self.wrap(center: center))
        assertSnapshot(
            of: host,
            as: .image(size: Self.size),
            named: "ToolbarProgress.Idle.light"
        )
    }

    @MainActor
    func testIndeterminate() {
        let center = ProgressCenter()
        _ = center.begin(label: "Fetching…")
        let host = Self.host(Self.wrap(center: center))
        assertSnapshot(
            of: host,
            as: .image(size: Self.size),
            named: "ToolbarProgress.Indeterminate.light"
        )
    }

    @MainActor
    func testDeterminate() {
        let center = ProgressCenter()
        let id = center.begin(label: "Receiving")
        center.update(id, percent: 42)
        let host = Self.host(Self.wrap(center: center))
        assertSnapshot(
            of: host,
            as: .image(size: Self.size),
            named: "ToolbarProgress.Determinate.light"
        )
    }

    // MARK: - Helpers

    @MainActor
    private static func wrap(center: ProgressCenter) -> some View {
        ToolbarProgressIndicator()
            .environment(center)
            .frame(width: size.width, height: size.height, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor))
    }

    @MainActor
    private static func host<V: View>(_ view: V) -> NSHostingController<V> {
        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(origin: .zero, size: size)
        // swiftlint:disable:next force_unwrapping
        host.view.appearance = NSAppearance(named: .aqua)!
        return host
    }
}
