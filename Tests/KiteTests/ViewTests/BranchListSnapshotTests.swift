import AppKit
import Foundation
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Kite

/// Snapshot coverage for the branch list view and row (VAL-BRANCH-001/002/
/// 003/004, VAL-UI-010 dark-mode parity).
///
/// Individual `BranchRow` states are snapshotted directly (rather than the
/// full `BranchListView`, which depends on environment state and `List`
/// recycling quirks that produce unstable reference images). The detached
/// HEAD banner is also snapshotted as a standalone HStack mirroring what
/// the view composes.
///
/// Per AGENTS.md "Established patterns": all hosted views force the
/// `NSHostingController`'s appearance to either `.aqua` (light) or
/// `.darkAqua` (dark) so `NSColor.windowBackgroundColor` actually resolves
/// to different bytes across light/dark. `preferredColorScheme` alone does
/// not carry into `NSColor`'s appearance lookup.
final class BranchListSnapshotTests: XCTestCase {
    private static let rowSize = CGSize(width: 320, height: 36)
    private static let bannerSize = CGSize(width: 320, height: 56)
    private static let listSize = CGSize(width: 320, height: 420)

    // MARK: - Empty state

    @MainActor
    func testEmptyState() {
        let view = ContentUnavailableView(
            "Select a repository",
            systemImage: "sidebar.left",
            description: Text("Choose a repo from the sidebar to see its branches.")
        )
        .frame(width: Self.listSize.width, height: Self.listSize.height)
        .background(Color(nsColor: .windowBackgroundColor))

        let host = Self.host(view, size: Self.listSize, appearance: .light)
        assertSnapshot(
            of: host,
            as: .image(size: Self.listSize),
            named: "BranchList.EmptyState.light"
        )
    }

    // MARK: - Local branches only (current + unpushed + in sync)

    @MainActor
    func testLocalBranchesOnly() {
        let branches = Self.sampleLocalBranches()
        let height = CGFloat(branches.count) * Self.rowSize.height
        let size = CGSize(width: Self.rowSize.width, height: height)
        let view = VStack(spacing: 0) {
            ForEach(branches, id: \.fullName) { branch in
                BranchRow(branch: branch)
                    .padding(.horizontal, 8)
                    .frame(height: Self.rowSize.height)
            }
        }
        .frame(width: Self.rowSize.width, height: height)
        .background(Color(nsColor: .windowBackgroundColor))

        let host = Self.host(view, size: size, appearance: .light)
        assertSnapshot(
            of: host,
            as: .image(size: size),
            named: "BranchList.LocalBranchesOnly.light"
        )
    }

    // MARK: - With remote branches

    @MainActor
    func testWithRemoteBranches() {
        let host = Self.host(Self.combinedView(), size: Self.combinedSize(), appearance: .light)
        assertSnapshot(
            of: host,
            as: .image(size: Self.combinedSize()),
            named: "BranchList.WithRemoteBranches.light"
        )
    }

    // MARK: - Detached HEAD banner

    @MainActor
    func testDetachedHead() {
        let view = HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("HEAD detached at abc1234")
                    .font(.body.weight(.semibold))
                Text("Create a branch to keep commits reachable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(width: Self.bannerSize.width, height: Self.bannerSize.height, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))

        let host = Self.host(view, size: Self.bannerSize, appearance: .light)
        assertSnapshot(
            of: host,
            as: .image(size: Self.bannerSize),
            named: "BranchList.DetachedHead.light"
        )
    }

    // MARK: - Dark-mode parity

    @MainActor
    func testDarkMode() {
        let host = Self.host(Self.combinedView(), size: Self.combinedSize(), appearance: .dark)
        assertSnapshot(
            of: host,
            as: .image(size: Self.combinedSize()),
            named: "BranchList.WithRemoteBranches.dark"
        )
    }

    // MARK: - Sample data

    private static func sampleLocalBranches() -> [Branch] {
        [
            Branch(
                shortName: "main",
                fullName: "refs/heads/main",
                sha: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                upstream: "origin/main",
                isRemote: false,
                remote: nil,
                ahead: 2,
                behind: 0,
                isGone: false,
                isHead: true
            ),
            Branch(
                shortName: "feature/a",
                fullName: "refs/heads/feature/a",
                sha: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                upstream: nil,
                isRemote: false,
                remote: nil,
                ahead: nil,
                behind: nil,
                isGone: false,
                isHead: false
            ),
            Branch(
                shortName: "feature/b",
                fullName: "refs/heads/feature/b",
                sha: "cccccccccccccccccccccccccccccccccccccccc",
                upstream: "origin/feature/b",
                isRemote: false,
                remote: nil,
                ahead: 0,
                behind: 0,
                isGone: true,
                isHead: false
            )
        ]
    }

    private static func sampleRemoteBranches() -> [Branch] {
        [
            Branch(
                shortName: "origin/feature/x",
                fullName: "refs/remotes/origin/feature/x",
                sha: "dddddddddddddddddddddddddddddddddddddddd",
                upstream: nil,
                isRemote: true,
                remote: "origin",
                ahead: nil,
                behind: nil,
                isGone: false,
                isHead: false
            ),
            Branch(
                shortName: "origin/main",
                fullName: "refs/remotes/origin/main",
                sha: "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
                upstream: nil,
                isRemote: true,
                remote: "origin",
                ahead: nil,
                behind: nil,
                isGone: false,
                isHead: false
            )
        ]
    }

    // MARK: - Host helpers

    /// Per-test hosting appearance. Converting to `NSAppearance` locally avoids
    /// a non-Sendable Swift type leaking into our call sites.
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
        appearance: HostAppearance
    ) -> NSHostingController<V> {
        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.appearance = appearance.appearance
        return host
    }

    @MainActor
    private static func combinedView() -> some View {
        let locals = sampleLocalBranches()
        let remotes = sampleRemoteBranches()

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(locals, id: \.fullName) { branch in
                BranchRow(branch: branch)
                    .padding(.horizontal, 8)
                    .frame(height: rowSize.height)
            }
            Divider()
            Text("origin")
                .font(.body.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 2)
            ForEach(remotes, id: \.fullName) { branch in
                BranchRow(branch: branch, isRemote: true)
                    .padding(.horizontal, 8)
                    .frame(height: rowSize.height)
            }
        }
        .frame(width: rowSize.width, height: combinedSize().height, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private static func combinedSize() -> CGSize {
        let totalRows = CGFloat(sampleLocalBranches().count + sampleRemoteBranches().count)
        let height = totalRows * rowSize.height + 40
        return CGSize(width: rowSize.width, height: height)
    }
}
