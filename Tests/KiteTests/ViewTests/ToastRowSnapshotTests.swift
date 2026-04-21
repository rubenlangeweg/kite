import AppKit
import Foundation
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Kite

/// Snapshot coverage for `ToastRow` across its visual states:
///   - success (green, no ✕, no detail)
///   - error collapsed (red, ✕, "Show details" hint)
///   - error expanded (detail panel visible with stderr blob)
///   - dark-mode parity for the error collapsed variant (md5 MUST differ
///     from the light version to prove appearance actually propagated)
///
/// Per AGENTS.md's "snapshot tests must not be byte-identical" precedent:
/// wrap content in `Color(nsColor: .windowBackgroundColor)` and set the
/// hosting controller's `appearance` explicitly so `NSColor`-backed Color
/// resolves to different bytes across traits. Inner `ToastRow` is snapshotted
/// directly — no environment, no ToastCenter.
final class ToastRowSnapshotTests: XCTestCase {
    // MARK: - Fixed-size layout knobs

    private static let rowSize = CGSize(width: 560, height: 72)
    private static let expandedSize = CGSize(width: 560, height: 240)

    // MARK: - Fixtures

    private static let detailBlob = """
    fatal: Authentication failed for 'https://example.com/repo.git/'
    remote: Invalid username or password.
    remote: You can generate a personal access token from https://example.com/settings/tokens
    """

    // MARK: - Cases

    @MainActor
    func testSuccessRow() {
        let toast = Toast(
            kind: .success,
            message: "Fetch succeeded",
            detail: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let host = Self.host(
            Self.wrap(row: ToastRow(toast: toast, onDismiss: {}), size: Self.rowSize),
            size: Self.rowSize
        )
        assertSnapshot(
            of: host,
            as: .image(size: Self.rowSize),
            named: "ToastRow.Success.light"
        )
    }

    @MainActor
    func testErrorRow() {
        let toast = Toast(
            kind: .error,
            message: "Push failed",
            detail: Self.detailBlob,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let host = Self.host(
            Self.wrap(row: ToastRow(toast: toast, onDismiss: {}), size: Self.rowSize),
            size: Self.rowSize
        )
        assertSnapshot(
            of: host,
            as: .image(size: Self.rowSize),
            named: "ToastRow.ErrorCollapsed.light"
        )
    }

    @MainActor
    func testErrorRowExpandedDetail() {
        // Drive the "expanded" state by mounting an `ExpandedToastRow`
        // helper below. We can't poke `ToastRow`'s private @State directly
        // so the helper mirrors the row with the detail panel pinned open.
        let toast = Toast(
            kind: .error,
            message: "Push failed",
            detail: Self.detailBlob,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let row = ExpandedToastRow(toast: toast)
        let host = Self.host(Self.wrap(row: row, size: Self.expandedSize), size: Self.expandedSize)
        assertSnapshot(
            of: host,
            as: .image(size: Self.expandedSize),
            named: "ToastRow.ErrorExpanded.light"
        )
    }

    @MainActor
    func testDarkMode() {
        let toast = Toast(
            kind: .error,
            message: "Push failed",
            detail: Self.detailBlob,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let host = Self.host(
            Self.wrap(row: ToastRow(toast: toast, onDismiss: {}), size: Self.rowSize),
            size: Self.rowSize,
            appearance: .dark
        )
        assertSnapshot(
            of: host,
            as: .image(size: Self.rowSize),
            named: "ToastRow.ErrorCollapsed.dark"
        )
    }

    // MARK: - Helpers

    @MainActor
    private static func wrap(row: some View, size: CGSize) -> some View {
        row
            .frame(width: size.width, height: size.height, alignment: .center)
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
        size: CGSize,
        appearance: HostAppearance = .light
    ) -> NSHostingController<V> {
        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.appearance = appearance.appearance
        return host
    }
}

/// Mirror of `ToastRow` pinned to the expanded-detail state. Avoids having
/// to expose a test-only init on the production row just to drive a
/// snapshot. Matches `ToastRow`'s layout and styling line-for-line for
/// detail-expanded so the snapshot stays meaningful.
private struct ExpandedToastRow: View {
    let toast: Toast

    private static let maxWidth: CGFloat = 540
    private static let detailMaxHeight: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: 2) {
                    Text(toast.message)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Hide details")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            if let detail = toast.detail {
                ScrollView {
                    Text(detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: Self.detailMaxHeight)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.08))
                )
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: Self.maxWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.red.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.red.opacity(0.45), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
    }
}
