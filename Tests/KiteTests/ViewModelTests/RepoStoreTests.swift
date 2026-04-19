import Foundation
import Testing
@testable import Kite

/// Tests for `RepoStore`, the app-level focused-repo owner.
///
/// Uses real fixture repos so the `RepoFocus` instantiated under the hood
/// can wire up a real FSWatcher. Each test is `@MainActor` to match
/// `RepoStore`'s isolation.
///
/// Fulfills: VAL-NET-009/010 (focus lifecycle portion) alongside
/// GitQueueTests + RepoFocusTests.
@Suite("RepoStore")
@MainActor
struct RepoStoreTests {
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

    private static func makeFixtureRepo(named name: String, under root: URL) throws -> DiscoveredRepo {
        let url = root.appendingPathComponent(name)
        try GitFixtureHelper.cleanRepo(at: url)
        return DiscoveredRepo(
            url: url,
            displayName: name,
            rootPath: root,
            isBare: false
        )
    }

    @Test("focus on nil clears state and persistence")
    func focusOnNilClearsState() throws {
        let root = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { GitFixtureHelper.cleanup(root) }

        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let store = PersistenceStore(defaults: defaults)
        let repo = try Self.makeFixtureRepo(named: "alpha", under: root)
        let repos = RepoStore(persistence: store)

        repos.focus(on: repo)
        #expect(repos.focus?.repo == repo)
        #expect(store.settings.lastOpenedRepo == repo.url.path)

        repos.focus(on: nil)

        #expect(repos.focus == nil)
        #expect(store.settings.lastOpenedRepo == nil)
    }

    @Test("focus on a repo instantiates a fresh RepoFocus and persists")
    func focusOnRepoStartsNewRepoFocus() throws {
        let root = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { GitFixtureHelper.cleanup(root) }

        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let store = PersistenceStore(defaults: defaults)
        let repo = try Self.makeFixtureRepo(named: "alpha", under: root)
        let repos = RepoStore(persistence: store)

        repos.focus(on: repo)

        #expect(repos.focus?.repo == repo)
        #expect(store.settings.lastOpenedRepo == repo.url.path)
        // Queue is keyed off the repo URL so downstream features can identify
        // the per-repo queue in logs.
        #expect(repos.focus?.queue.repoURL == repo.url)
    }

    @Test("switching repos replaces focus cleanly with no crash")
    func switchingReposReplacesFocus() throws {
        let root = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { GitFixtureHelper.cleanup(root) }

        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let store = PersistenceStore(defaults: defaults)
        let repoA = try Self.makeFixtureRepo(named: "alpha", under: root)
        let repoB = try Self.makeFixtureRepo(named: "bravo", under: root)
        let repos = RepoStore(persistence: store)

        repos.focus(on: repoA)
        let firstFocus = repos.focus
        #expect(firstFocus?.repo == repoA)

        repos.focus(on: repoB)
        let secondFocus = repos.focus

        #expect(secondFocus?.repo == repoB)
        // Instances must be distinct — a new RepoFocus is created per swap.
        #expect(firstFocus !== secondFocus)
        #expect(store.settings.lastOpenedRepo == repoB.url.path)
    }

    @Test("persistence's lastOpenedRepo reflects the latest focus")
    func persistenceUpdates() throws {
        let root = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { GitFixtureHelper.cleanup(root) }

        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let store = PersistenceStore(defaults: defaults)
        let repoA = try Self.makeFixtureRepo(named: "alpha", under: root)
        let repoB = try Self.makeFixtureRepo(named: "bravo", under: root)
        let repos = RepoStore(persistence: store)

        repos.focus(on: repoA)
        #expect(store.settings.lastOpenedRepo == repoA.url.path)

        repos.focus(on: repoB)
        #expect(store.settings.lastOpenedRepo == repoB.url.path)

        repos.focus(on: nil)
        #expect(store.settings.lastOpenedRepo == nil)
    }
}
