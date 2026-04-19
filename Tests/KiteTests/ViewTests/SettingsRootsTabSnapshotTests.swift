import Foundation
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Kite

/// Snapshot tests for `SettingsRootsTab`.
///
/// To keep references stable across developer machines we host the tab inside
/// a fixed-size `NSHostingController` and wire it to isolated `UserDefaults`
/// + a stub `RepoSidebarModel`. The underlying `SettingsRootsModel` pulls
/// status from the filesystem; the cases that need "missing" coverage use
/// paths that are guaranteed not to exist on the test host.
///
/// Fulfills VAL-REPO-003 / VAL-REPO-005 / VAL-UI-010 snapshot coverage.
final class SettingsRootsTabSnapshotTests: XCTestCase {
    private static let tabSize = CGSize(width: 520, height: 380)

    @MainActor
    private func makeStore(extraRoots: [String] = [], suite: String) -> PersistenceStore {
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("Could not create UserDefaults suite '\(suite)'")
        }
        defaults.removePersistentDomain(forName: suite)

        // Pre-seed an extra-roots blob bypassing `addExtraRoot` validation so
        // snapshot cases can include intentionally-missing paths. The schema
        // here must match `KiteSettings.current`.
        var seed = KiteSettings.default
        seed.extraRoots = extraRoots
        if let data = try? JSONEncoder().encode(seed) {
            defaults.set(data, forKey: PersistenceKeys.settingsBlob)
        }

        return PersistenceStore(defaults: defaults)
    }

    @MainActor
    private func hostView(
        persistence: PersistenceStore,
        sidebarModel: RepoSidebarModel,
        colorScheme: ColorScheme
    ) -> NSHostingController<AnyView> {
        let view = AnyView(
            SettingsRootsTab()
                .environment(persistence)
                .environment(sidebarModel)
                .frame(width: Self.tabSize.width, height: Self.tabSize.height)
                .preferredColorScheme(colorScheme)
        )
        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(origin: .zero, size: Self.tabSize)
        return host
    }

    @MainActor
    private func makeSidebarModel(for persistence: PersistenceStore) -> RepoSidebarModel {
        RepoSidebarModel(
            persistence: persistence,
            rootsOverride: [URL(fileURLWithPath: "/tmp/kite-snapshots")],
            scanner: { _ in [] }
        )
    }

    @MainActor
    func testEmptyExtraRoots() {
        let store = makeStore(extraRoots: [], suite: "snap-empty-\(UUID().uuidString)")
        let sidebar = makeSidebarModel(for: store)
        let host = hostView(persistence: store, sidebarModel: sidebar, colorScheme: .light)
        assertSnapshot(
            of: host,
            as: .image(size: Self.tabSize),
            named: "SettingsRootsTab.empty.light"
        )
    }

    @MainActor
    func testWithTwoExtraRoots() throws {
        let tmp1 = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp1) }
        let tmp2 = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp2) }

        let store = makeStore(
            extraRoots: [tmp1.path, tmp2.path],
            suite: "snap-two-\(UUID().uuidString)"
        )
        let sidebar = makeSidebarModel(for: store)
        let host = hostView(persistence: store, sidebarModel: sidebar, colorScheme: .light)
        assertSnapshot(
            of: host,
            as: .image(size: Self.tabSize),
            named: "SettingsRootsTab.twoExtraRoots.light"
        )
    }

    @MainActor
    func testWithMissingExtraRoot() throws {
        let tmp = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let ghost = "/tmp/kite-missing-\(UUID().uuidString)"

        let store = makeStore(
            extraRoots: [tmp.path, ghost],
            suite: "snap-missing-\(UUID().uuidString)"
        )
        let sidebar = makeSidebarModel(for: store)
        let host = hostView(persistence: store, sidebarModel: sidebar, colorScheme: .light)
        assertSnapshot(
            of: host,
            as: .image(size: Self.tabSize),
            named: "SettingsRootsTab.missingExtraRoot.light"
        )
    }

    @MainActor
    func testWithTwoExtraRootsDarkMode() throws {
        let tmp1 = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp1) }
        let tmp2 = try tempDir()
        defer { try? FileManager.default.removeItem(at: tmp2) }

        let store = makeStore(
            extraRoots: [tmp1.path, tmp2.path],
            suite: "snap-two-dark-\(UUID().uuidString)"
        )
        let sidebar = makeSidebarModel(for: store)
        let host = hostView(persistence: store, sidebarModel: sidebar, colorScheme: .dark)
        assertSnapshot(
            of: host,
            as: .image(size: Self.tabSize),
            named: "SettingsRootsTab.twoExtraRoots.dark"
        )
    }

    // MARK: - Fixtures

    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kite-settings-snap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
