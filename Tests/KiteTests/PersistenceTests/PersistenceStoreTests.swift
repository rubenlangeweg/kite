import CoreGraphics
import Foundation
import Testing
@testable import Kite

/// Tests for `PersistenceStore`.
///
/// Isolation strategy: every test creates its own `UserDefaults(suiteName:)`
/// keyed off a fresh UUID and tears the suite down in a deferred block. We
/// never touch `.standard` so parallel tests are safe and no state leaks out
/// of the process.
///
/// Fulfills VAL-PERSIST-001..005.
@Suite("PersistenceStore")
@MainActor
struct PersistenceStoreTests {
    /// Creates a fresh UserDefaults tied to a unique suite name, plus a
    /// cleanup closure the caller should defer.
    private static func makeDefaults() -> (UserDefaults, () -> Void) {
        let suiteName = "test-" + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create UserDefaults suite '\(suiteName)'")
        }
        let cleanup = {
            defaults.removePersistentDomain(forName: suiteName)
            defaults.synchronize()
        }
        return (defaults, cleanup)
    }

    // MARK: - 1. Defaults on first launch

    @Test("first-launch load returns canonical defaults")
    func defaultSettingsOnFirstLaunch() {
        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let store = PersistenceStore(defaults: defaults)

        #expect(store.settings.autoFetchEnabled == true)
        #expect(store.settings.pinnedRepos.isEmpty)
        #expect(store.settings.extraRoots.isEmpty)
        #expect(store.settings.lastOpenedRepo == nil)
        #expect(store.settings.lastSelectedBranch.isEmpty)
        #expect(store.settings.windowFrame == nil)
        #expect(store.settings.sidebarWidth == nil)
        #expect(store.settings.detailWidth == nil)
        #expect(store.settings.schemaVersion == KiteSettings.current)
    }

    // MARK: - 2. Round trip every field

    @Test("every field survives save-then-reload into a fresh store")
    func roundTripAllFields() throws {
        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let store = PersistenceStore(defaults: defaults)
        store.pin("/Users/ruben/Developer/kite")
        store.pin("/Users/ruben/Developer/alpha")
        try store.addExtraRoot(FileManager.default.temporaryDirectory.path)
        store.setLastOpenedRepo("/Users/ruben/Developer/kite")
        store.setLastSelectedBranch("main", forRepo: "/Users/ruben/Developer/kite")
        store.setLastSelectedBranch("feature-x", forRepo: "/Users/ruben/Developer/alpha")
        store.setWindowFrame(CGRect(x: 80, y: 120, width: 1280, height: 800))
        store.setSidebarWidth(240)
        store.setDetailWidth(520)
        store.setAutoFetchEnabled(false)

        let rehydrated = PersistenceStore(defaults: defaults)

        #expect(rehydrated.settings.pinnedRepos == store.settings.pinnedRepos)
        #expect(rehydrated.settings.extraRoots == store.settings.extraRoots)
        #expect(rehydrated.settings.lastOpenedRepo == "/Users/ruben/Developer/kite")
        #expect(rehydrated.settings.lastSelectedBranch["/Users/ruben/Developer/kite"] == "main")
        #expect(rehydrated.settings.lastSelectedBranch["/Users/ruben/Developer/alpha"] == "feature-x")
        #expect(rehydrated.settings.windowFrame?.cgRect == CGRect(x: 80, y: 120, width: 1280, height: 800))
        #expect(rehydrated.settings.sidebarWidth == 240)
        #expect(rehydrated.settings.detailWidth == 520)
        #expect(rehydrated.settings.autoFetchEnabled == false)
        #expect(rehydrated.settings.schemaVersion == KiteSettings.current)
    }

    // MARK: - 3. Pin / unpin semantics

    @Test("pin is idempotent and unpin removes")
    func pinAndUnpin() {
        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let store = PersistenceStore(defaults: defaults)
        store.pin("/a")
        store.pin("/b")
        store.pin("/a") // duplicate — should be ignored
        #expect(store.settings.pinnedRepos == ["/a", "/b"])

        store.unpin("/a")
        #expect(store.settings.pinnedRepos == ["/b"])
    }

    // MARK: - 4. Extra root rejects non-existent path

    @Test("addExtraRoot throws on non-existent path")
    func addExtraRootRejectsNonExistent() {
        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let store = PersistenceStore(defaults: defaults)
        let bogus = "/definitely/does/not/exist-\(UUID().uuidString)"

        #expect(throws: PersistenceStore.ExtraRootError.self) {
            try store.addExtraRoot(bogus)
        }
        #expect(store.settings.extraRoots.isEmpty)
    }

    // MARK: - 5. Extra root rejects a file (must be directory)

    @Test("addExtraRoot throws when the path is a regular file")
    func addExtraRootRejectsNonDirectory() throws {
        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("kite-root-\(UUID().uuidString).txt")
        try "i am a file, not a directory".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let store = PersistenceStore(defaults: defaults)
        #expect(throws: PersistenceStore.ExtraRootError.self) {
            try store.addExtraRoot(file.path)
        }
        #expect(store.settings.extraRoots.isEmpty)
    }

    // MARK: - 6. Schema version persists, migration is no-op for current

    @Test("schemaVersion is persisted as KiteSettings.current and migration is a no-op on load")
    func schemaVersionPresentAndMigrationNoOpForCurrentVersion() {
        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let store = PersistenceStore(defaults: defaults)
        store.pin("/a")
        #expect(store.settings.schemaVersion == KiteSettings.current)

        let rehydrated = PersistenceStore(defaults: defaults)
        #expect(rehydrated.settings.schemaVersion == KiteSettings.current)
        #expect(rehydrated.settings.pinnedRepos == ["/a"])
    }

    // MARK: - 7. Missing key returns defaults (and persists them)

    @Test("brand-new suite returns defaults and writes them back for the next load")
    func missingKeyReturnsDefaults() {
        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        // Sanity: no blob key present before construction.
        #expect(defaults.data(forKey: PersistenceKeys.settingsBlob) == nil)

        let store = PersistenceStore(defaults: defaults)
        #expect(store.settings == KiteSettings.default)

        // The store should have written defaults through to defaults so the
        // next construction reads them without re-hitting the fallback path.
        #expect(defaults.data(forKey: PersistenceKeys.settingsBlob) != nil)
    }

    // MARK: - 8. Per-repo last-selected-branch

    @Test("last-selected branch is stored and recovered per repo")
    func lastSelectedBranchPerRepo() {
        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let store = PersistenceStore(defaults: defaults)
        store.setLastSelectedBranch("main", forRepo: "/repo/a")
        store.setLastSelectedBranch("develop", forRepo: "/repo/b")

        let rehydrated = PersistenceStore(defaults: defaults)
        #expect(rehydrated.settings.lastSelectedBranch["/repo/a"] == "main")
        #expect(rehydrated.settings.lastSelectedBranch["/repo/b"] == "develop")
    }

    // MARK: - 9. Corrupt-blob resilience

    @Test("unparseable blob triggers a silent fallback to defaults")
    func unparseableBlobFallsBackToDefaults() {
        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        // Seed garbage at the blob key before constructing the store.
        let garbage = Data("{this is not json".utf8)
        defaults.set(garbage, forKey: PersistenceKeys.settingsBlob)

        let store = PersistenceStore(defaults: defaults)

        #expect(store.settings == KiteSettings.default)
        // And the defaults should have been written back over the garbage.
        if let data = defaults.data(forKey: PersistenceKeys.settingsBlob) {
            let decoded = try? JSONDecoder().decode(KiteSettings.self, from: data)
            #expect(decoded == KiteSettings.default)
        } else {
            Issue.record("Expected defaults to be persisted after corrupt-blob recovery")
        }
    }
}
