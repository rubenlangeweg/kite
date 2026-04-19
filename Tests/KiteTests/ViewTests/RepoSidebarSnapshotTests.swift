import Foundation
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Kite

/// Snapshot tests for the repo sidebar (VAL-UI-007, VAL-UI-010).
///
/// Rationale for using XCTest rather than Swift Testing: the
/// `pointfreeco/swift-snapshot-testing` library is XCTest-based. The
/// test suite lives alongside Swift Testing suites in the same target —
/// both coexist per `library/swiftui-macos.md` §10.2.
///
/// Snapshot sizes are pinned to a typical sidebar footprint (260×600) so
/// references are stable across Macs. Reference images must be visually
/// reviewed before merge; see the handoff for the explicit note.
final class RepoSidebarSnapshotTests: XCTestCase {
    private static let sidebarSize = CGSize(width: 260, height: 600)

    @MainActor
    func testEmptyState() {
        let view = EmptyRepoList(defaultRootDisplay: "~/Developer")
            .frame(width: Self.sidebarSize.width, height: Self.sidebarSize.height)
            .preferredColorScheme(.light)
        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(origin: .zero, size: Self.sidebarSize)
        assertSnapshot(of: host, as: .image(size: Self.sidebarSize), named: "EmptyState.light")
    }

    @MainActor
    func testEmptyStateDarkMode() {
        let view = EmptyRepoList(defaultRootDisplay: "~/Developer")
            .frame(width: Self.sidebarSize.width, height: Self.sidebarSize.height)
            .preferredColorScheme(.dark)
        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(origin: .zero, size: Self.sidebarSize)
        assertSnapshot(of: host, as: .image(size: Self.sidebarSize), named: "EmptyState.dark")
    }

    @MainActor
    func testRepoRowWorkTree() {
        let repo = DiscoveredRepo(
            url: URL(fileURLWithPath: "/Users/tester/Developer/alpha"),
            displayName: "alpha",
            rootPath: URL(fileURLWithPath: "/Users/tester/Developer"),
            isBare: false
        )
        let rowSize = CGSize(width: Self.sidebarSize.width, height: 44)
        let view = RepoRow(repo: repo)
            .padding(8)
            .frame(width: rowSize.width, height: rowSize.height)
            .preferredColorScheme(.light)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(origin: .zero, size: rowSize)
        assertSnapshot(of: host, as: .image(size: rowSize), named: "RepoRow.workTree.light")
    }

    @MainActor
    func testRepoRowBare() {
        let repo = DiscoveredRepo(
            url: URL(fileURLWithPath: "/Users/tester/Developer/server.git"),
            displayName: "server.git",
            rootPath: URL(fileURLWithPath: "/Users/tester/Developer"),
            isBare: true
        )
        let rowSize = CGSize(width: Self.sidebarSize.width, height: 44)
        let view = RepoRow(repo: repo)
            .padding(8)
            .frame(width: rowSize.width, height: rowSize.height)
            .preferredColorScheme(.light)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(origin: .zero, size: rowSize)
        assertSnapshot(of: host, as: .image(size: rowSize), named: "RepoRow.bare.light")
    }

    @MainActor
    func testRepoRowDarkMode() {
        let repo = DiscoveredRepo(
            url: URL(fileURLWithPath: "/Users/tester/Developer/alpha"),
            displayName: "alpha",
            rootPath: URL(fileURLWithPath: "/Users/tester/Developer"),
            isBare: false
        )
        let rowSize = CGSize(width: Self.sidebarSize.width, height: 44)
        let view = RepoRow(repo: repo)
            .padding(8)
            .frame(width: rowSize.width, height: rowSize.height)
            .preferredColorScheme(.dark)

        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(origin: .zero, size: rowSize)
        assertSnapshot(of: host, as: .image(size: rowSize), named: "RepoRow.dark")
    }
}
