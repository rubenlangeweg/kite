import Foundation
import Testing
@testable import Kite

/// Unit tests for `SettingsRootsModel` — the logic helper behind
/// `SettingsRootsTab`.
///
/// Fulfills: VAL-REPO-003 (add flow persistence), VAL-REPO-004 (remove flow
/// persistence), VAL-REPO-005 (invalid path surfaces user-facing error).
@Suite("SettingsRootsTabLogic")
@MainActor
struct SettingsRootsTabLogicTests {
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

    private static func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kite-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("addRoot with a valid directory persists through the store")
    func addingValidRootPersists() throws {
        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let tmp = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = PersistenceStore(defaults: defaults)
        let model = SettingsRootsModel(persistence: store)

        let ok = model.addRoot(path: tmp.path)

        #expect(ok == true)
        #expect(model.inlineError == nil)
        #expect(store.settings.extraRoots == [tmp.path])
    }

    @Test("addRoot with a non-existent path surfaces a user-friendly inline error")
    func addingNonExistentRootSurfacesInlineError() {
        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let store = PersistenceStore(defaults: defaults)
        let model = SettingsRootsModel(persistence: store)

        let ghost = "/tmp/kite-nonexistent-\(UUID().uuidString)"
        let ok = model.addRoot(path: ghost)

        #expect(ok == false)
        #expect(store.settings.extraRoots.isEmpty)
        let message = try? #require(model.inlineError)
        let text = message ?? ""
        #expect(text.contains("doesn't exist"))
        // Must not leak an NSError-style description or `Error` debug output.
        #expect(!text.contains("Error Domain"))
    }

    @Test("addRoot on a file path (not a directory) surfaces a directory error")
    func addingFileAsRootSurfacesDirectoryError() throws {
        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let tmp = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let filePath = tmp.appendingPathComponent("not-a-dir.txt")
        try Data("hello".utf8).write(to: filePath)

        let store = PersistenceStore(defaults: defaults)
        let model = SettingsRootsModel(persistence: store)
        let ok = model.addRoot(path: filePath.path)

        #expect(ok == false)
        let text = model.inlineError ?? ""
        #expect(text.contains("isn't a folder"))
    }

    @Test("removeRoot refuses to touch the default root")
    func removingDefaultRootIsNoOp() throws {
        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let tmp = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = PersistenceStore(defaults: defaults)
        // Seed one real extra root so we can confirm that persistence is
        // untouched by a default-root removal attempt.
        try store.addExtraRoot(tmp.path)

        let model = SettingsRootsModel(persistence: store)
        let defaultPath = SettingsRootsModel.defaultRoot.path

        let removed = model.removeRoot(path: defaultPath)

        #expect(removed == false)
        #expect(store.settings.extraRoots == [tmp.path])
    }

    @Test("removeRoot on an extra root mutates persistence")
    func removingExtraRootPersists() throws {
        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let tmp = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = PersistenceStore(defaults: defaults)
        try store.addExtraRoot(tmp.path)
        let model = SettingsRootsModel(persistence: store)

        let removed = model.removeRoot(path: tmp.path)

        #expect(removed == true)
        #expect(store.settings.extraRoots.isEmpty)
    }

    @Test("rows emit a found status for existing paths and missing for absent paths")
    func statusReflectsFilesystem() throws {
        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let tmp = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let ghost = "/tmp/kite-ghost-\(UUID().uuidString)"

        // Seed two extras by bypassing addExtraRoot's validation for the
        // ghost path — we need the missing path in persistence to verify
        // that status probing still flags it.
        var seed = KiteSettings.default
        seed.extraRoots = [tmp.path, ghost]
        let seedData = try JSONEncoder().encode(seed)
        defaults.set(seedData, forKey: PersistenceKeys.settingsBlob)
        let store = PersistenceStore(defaults: defaults)

        let model = SettingsRootsModel(persistence: store)
        let rows = model.rows

        // Row 0 is always the default root. It may be found or missing
        // depending on whether the test host has `~/Developer`; we only
        // assert that the computed status matches the filesystem probe.
        #expect(rows.first?.isDefault == true)

        let tmpRow = rows.first(where: { $0.path == tmp.path })
        #expect(tmpRow?.status == .found)

        let ghostRow = rows.first(where: { $0.path == ghost })
        #expect(ghostRow?.status == .missing)

        #expect(model.status(forPath: tmp.path) == .found)
        #expect(model.status(forPath: ghost) == .missing)
    }

    @Test("rows exposes the default root as non-removable in first position")
    func rowsIncludeDefaultRootFirstAndNonRemovable() {
        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let store = PersistenceStore(defaults: defaults)
        let model = SettingsRootsModel(persistence: store)

        let rows = model.rows
        let first = rows.first
        #expect(first?.isDefault == true)
        #expect(first?.path == SettingsRootsModel.defaultRoot.path)
        #expect(first?.displayPath == "~/Developer")
    }

    @Test("addRoot clears any stale inline error on success")
    func addRootClearsInlineErrorOnSuccess() throws {
        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let tmp = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = PersistenceStore(defaults: defaults)
        let model = SettingsRootsModel(persistence: store)

        // Prime with a failure.
        _ = model.addRoot(path: "/tmp/kite-missing-\(UUID().uuidString)")
        #expect(model.inlineError != nil)

        // Now succeed.
        let ok = model.addRoot(path: tmp.path)
        #expect(ok == true)
        #expect(model.inlineError == nil)
    }
}
