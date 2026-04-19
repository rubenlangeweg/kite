import Foundation
import Testing
@testable import Kite

/// Unit tests for `RepoSidebarModel`.
///
/// Uses isolated `UserDefaults(suiteName:)` per test (same pattern as
/// `PersistenceStoreTests`) plus an injected in-memory scanner so tests
/// run without hitting the filesystem.
///
/// Fulfills: VAL-REPO-008 (last selection restore), VAL-REPO-009 (pinning),
/// plus the view-model correctness portion of VAL-REPO-007.
@Suite("RepoSidebarModel")
@MainActor
struct RepoSidebarModelTests {
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

    private static func makeRepo(
        name: String,
        root: URL,
        isBare: Bool = false
    ) -> DiscoveredRepo {
        DiscoveredRepo(
            url: root.appendingPathComponent(name),
            displayName: name,
            rootPath: root,
            isBare: isBare
        )
    }

    private static func makeModel(
        persistence: PersistenceStore,
        rootsOverride: [URL],
        fixture: [DiscoveredRepo]
    ) -> RepoSidebarModel {
        let captured = fixture
        return RepoSidebarModel(
            persistence: persistence,
            rootsOverride: rootsOverride,
            scanner: { _ in captured }
        )
    }

    @Test("refresh populates discoveredByRoot grouped by the rootPath")
    func refreshPopulatesDiscoveredByRoot() async {
        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let rootA = URL(fileURLWithPath: "/tmp/kite-fixture-a")
        let rootB = URL(fileURLWithPath: "/tmp/kite-fixture-b")
        let repos = [
            Self.makeRepo(name: "alpha", root: rootA),
            Self.makeRepo(name: "beta", root: rootA),
            Self.makeRepo(name: "gamma", root: rootB)
        ]
        let store = PersistenceStore(defaults: defaults)
        let model = Self.makeModel(persistence: store, rootsOverride: [rootA, rootB], fixture: repos)

        await model.refresh()

        #expect(model.rootSections.count == 2)
        #expect(model.rootSections[0].root == rootA.standardizedFileURL)
        #expect(model.rootSections[0].repos.map(\.displayName) == ["alpha", "beta"])
        #expect(model.rootSections[1].root == rootB.standardizedFileURL)
        #expect(model.rootSections[1].repos.map(\.displayName) == ["gamma"])
        #expect(model.isScanning == false)
    }

    @Test("pin writes the repo path to persistence and surfaces in model.pinned")
    func pinAddsToPersistence() async {
        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let root = URL(fileURLWithPath: "/tmp/kite-fixture")
        let repo = Self.makeRepo(name: "alpha", root: root)
        let store = PersistenceStore(defaults: defaults)
        let model = Self.makeModel(persistence: store, rootsOverride: [root], fixture: [repo])

        await model.refresh()
        model.pin(repo)

        #expect(store.settings.pinnedRepos == [repo.url.path])
        #expect(model.pinned.map(\.displayName) == ["alpha"])
    }

    @Test("unpin removes the path from persistence and pinned list")
    func unpinRemovesFromPersistence() async {
        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let root = URL(fileURLWithPath: "/tmp/kite-fixture")
        let repo = Self.makeRepo(name: "alpha", root: root)
        let store = PersistenceStore(defaults: defaults)
        store.pin(repo.url.path)
        let model = Self.makeModel(persistence: store, rootsOverride: [root], fixture: [repo])

        await model.refresh()
        #expect(model.pinned.map(\.displayName) == ["alpha"])

        model.unpin(repo)

        #expect(store.settings.pinnedRepos.isEmpty)
        #expect(model.pinned.isEmpty)
    }

    @Test("select writes last-opened repo path")
    func selectWritesLastOpenedRepo() async {
        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let root = URL(fileURLWithPath: "/tmp/kite-fixture")
        let repo = Self.makeRepo(name: "alpha", root: root)
        let store = PersistenceStore(defaults: defaults)
        let model = Self.makeModel(persistence: store, rootsOverride: [root], fixture: [repo])

        await model.refresh()
        model.select(repo)

        #expect(model.selectedRepo == repo)
        #expect(store.settings.lastOpenedRepo == repo.url.path)

        model.select(nil)
        #expect(store.settings.lastOpenedRepo == nil)
    }

    @Test("select forwards to RepoStore when one is wired up")
    func selectForwardsToRepoStore() async throws {
        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        // Use a real fixture repo so RepoStore's RepoFocus can wire up a real
        // FSWatcher without throwing. RepoStore is exercised against the
        // same PersistenceStore to confirm last-opened-repo round-trip.
        let fixtureRoot = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { GitFixtureHelper.cleanup(fixtureRoot) }
        let repoURL = fixtureRoot.appendingPathComponent("alpha")
        try GitFixtureHelper.cleanRepo(at: repoURL)

        let repo = DiscoveredRepo(
            url: repoURL,
            displayName: "alpha",
            rootPath: fixtureRoot,
            isBare: false
        )

        let store = PersistenceStore(defaults: defaults)
        let repoStore = RepoStore(persistence: store)
        let model = RepoSidebarModel(
            persistence: store,
            repoStore: repoStore,
            rootsOverride: [fixtureRoot],
            scanner: { _ in [repo] }
        )

        await model.refresh()
        model.select(repo)

        #expect(repoStore.focus?.repo == repo)
        #expect(store.settings.lastOpenedRepo == repo.url.path)

        model.select(nil)
        #expect(repoStore.focus == nil)
        #expect(store.settings.lastOpenedRepo == nil)
    }

    @Test("restoreLastSelection picks up the persisted path after refresh")
    func restoreLastSelectionFindsMatchingRepo() async {
        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let root = URL(fileURLWithPath: "/tmp/kite-fixture")
        let repo = Self.makeRepo(name: "alpha", root: root)
        let store = PersistenceStore(defaults: defaults)
        store.setLastOpenedRepo(repo.url.path)
        let model = Self.makeModel(persistence: store, rootsOverride: [root], fixture: [repo])

        await model.refresh()
        await model.restoreLastSelection()

        #expect(model.selectedRepo == repo)
    }

    @Test("restoreLastSelection leaves selection nil when the repo no longer exists")
    func restoreLastSelectionWhenRepoMissing() async {
        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let root = URL(fileURLWithPath: "/tmp/kite-fixture")
        let repo = Self.makeRepo(name: "alpha", root: root)
        let store = PersistenceStore(defaults: defaults)
        store.setLastOpenedRepo("/tmp/long-gone/missing-repo")
        let model = Self.makeModel(persistence: store, rootsOverride: [root], fixture: [repo])

        await model.refresh()
        await model.restoreLastSelection()

        #expect(model.selectedRepo == nil)
        // Persistence retains the path for a future rescan.
        #expect(store.settings.lastOpenedRepo == "/tmp/long-gone/missing-repo")
    }

    @Test("pinned paths that are not currently discovered are excluded from model.pinned")
    func pinnedPathsNotDiscoveredAreExcluded() async {
        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let root = URL(fileURLWithPath: "/tmp/kite-fixture")
        let repo = Self.makeRepo(name: "alpha", root: root)
        let store = PersistenceStore(defaults: defaults)
        store.pin(repo.url.path)
        store.pin("/tmp/ghost/not-on-disk")
        let model = Self.makeModel(persistence: store, rootsOverride: [root], fixture: [repo])

        await model.refresh()

        #expect(model.pinned.map(\.displayName) == ["alpha"])
        // Persistence is untouched — the ghost path is retained for a future scan.
        #expect(store.settings.pinnedRepos.contains("/tmp/ghost/not-on-disk"))
    }

    @Test("empty scan produces empty groups and triggers hasAnyRepos=false")
    func emptyScanEmptyModel() async {
        let (defaults, cleanup) = Self.makeDefaults()
        defer { cleanup() }

        let store = PersistenceStore(defaults: defaults)
        let model = Self.makeModel(
            persistence: store,
            rootsOverride: [URL(fileURLWithPath: "/tmp/kite-fixture")],
            fixture: []
        )

        await model.refresh()

        #expect(model.discoveredByRoot.isEmpty)
        #expect(model.pinned.isEmpty)
        #expect(model.hasAnyRepos == false)
    }
}
