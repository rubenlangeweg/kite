import AppKit
import Foundation
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Kite

/// Snapshot coverage for the About tab (VAL-UI-008, VAL-UI-010,
/// VAL-PKG-003). Two cases — light and dark — follow the
/// `CommitDiffSnapshotTests` recipe that survived the M3 snapshot-
/// degeneracy fallout. Specifically:
///
///   - `NSHostingController.view.appearance` is set explicitly so
///     dark/light parity tests actually reflect `NSColor`-backed
///     backgrounds rather than defaulting to the host's appearance.
///   - Content wraps in `Color(nsColor: .windowBackgroundColor)` so the
///     appearance swap yields visibly distinct bytes across modes.
///   - We snapshot the presentational view directly — no environment,
///     no fixtures, no `NSApp`.
///
/// md5-distinctness is expected between the two cases. See AGENTS.md
/// "Snapshot tests must not be byte-identical across cases".
///
/// Listed in the M8-fix-snapshot-degeneracy skip-list (AGENTS.md) by
/// the validation gate until references are re-recorded in CI. Kept
/// authored here so the recording machinery is in place the day the
/// skip list retires.
final class SettingsAboutTabSnapshotTests: XCTestCase {
    private static let width: CGFloat = 420
    private static let height: CGFloat = 340

    // MARK: - Cases

    @MainActor
    func testLight() {
        let host = Self.host(SettingsAboutTab(), appearance: .light)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: Self.width, height: Self.height)),
            named: "SettingsAbout.light"
        )
    }

    @MainActor
    func testDark() {
        let host = Self.host(SettingsAboutTab(), appearance: .dark)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: Self.width, height: Self.height)),
            named: "SettingsAbout.dark"
        )
    }

    // MARK: - Helpers

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
    private static func host(_ view: some View, appearance: HostAppearance)
        -> NSHostingController<AnyView>
    {
        let wrapped = AnyView(
            view
                .frame(width: width, height: height)
                .background(Color(nsColor: .windowBackgroundColor))
        )
        let host = NSHostingController(rootView: wrapped)
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        host.view.appearance = appearance.appearance
        return host
    }
}
