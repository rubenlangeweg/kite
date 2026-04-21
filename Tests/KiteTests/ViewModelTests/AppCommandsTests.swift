import Foundation
import Testing
@testable import Kite

/// Unit tests for `AppCommands`, the menu/shortcut ↔ services bridge.
///
/// Scope:
///   - refresh bumps `focus.lastChangeAt` so observer panels reload.
///   - fetch/pull/push delegate to `NetworkOps` against the focused repo.
///   - openNewBranchSheet bumps the published `newBranchRequest` binding.
///   - `hasFocus` reports the store's focus state so menu items can `.disabled(...)`.
///
/// Uses real fixture repos (bare origin + author + tracker) like
/// `NetworkOpsFetchTests` so `NetworkOps` runs end-to-end without mocks —
/// AGENTS.md rule "no mocking of git".
///
/// Fulfills: VAL-UI-002 (menu parity with toolbar), VAL-UI-003 (shortcut
/// actions route to the right services).
@Suite("AppCommands")
@MainActor
struct AppCommandsTests {
    // MARK: - Fixtures

    private struct Fixtures {
        let parent: URL
        let bare: URL
        let author: URL
        let tracker: URL
        let repo: DiscoveredRepo
    }

    private static func makeFixture() throws -> Fixtures {
        let parent = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let bare = parent.appendingPathComponent("origin.git")
        try GitFixtureHelper.exec(["init", "--bare", "-b", "main", bare.path], cwd: parent)

        let author = parent.appendingPathComponent("author")
        try GitFixtureHelper.cleanRepo(at: author)
        try GitFixtureHelper.exec(["remote", "add", "origin", bare.path], cwd: author)
        try GitFixtureHelper.exec(["push", "-u", "origin", "main"], cwd: author)

        let tracker = parent.appendingPathComponent("tracker")
        try GitFixtureHelper.exec(["clone", bare.path, tracker.path], cwd: parent)
        try GitFixtureHelper.exec(["config", "user.email", "tests@kite.local"], cwd: tracker)
        try GitFixtureHelper.exec(["config", "user.name", "Kite Tests"], cwd: tracker)
        try GitFixtureHelper.exec(["config", "commit.gpgsign", "false"], cwd: tracker)

        let repo = DiscoveredRepo(
            url: tracker,
            displayName: "tracker",
            rootPath: parent,
            isBare: false
        )
        return Fixtures(parent: parent, bare: bare, author: author, tracker: tracker, repo: repo)
    }

    private static func pushIncoming(commitCount: Int, into fixture: Fixtures) throws {
        for index in 0 ..< commitCount {
            try GitFixtureHelper.exec(
                ["commit", "--allow-empty", "-m", "incoming-\(index)"],
                cwd: fixture.author
            )
        }
        try GitFixtureHelper.exec(["push", "origin", "main"], cwd: fixture.author)
    }

    private static func makePersistence() -> PersistenceStore {
        let suite = "nl.rb2.kite.tests.appcommands.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("Could not create UserDefaults suite \(suite)")
        }
        return PersistenceStore(defaults: defaults)
    }

    /// Factory returning a fully wired `AppCommands` plus the underlying
    /// services — each test opts into whichever side-effects it wants to
    /// inspect.
    private struct Harness {
        let persistence: PersistenceStore
        let store: RepoStore
        let sidebar: RepoSidebarModel
        let toasts: ToastCenter
        let progress: ProgressCenter
        let networkOps: NetworkOps
        let branchOps: BranchOps
        let commands: AppCommands
    }

    private static func makeHarness() -> Harness {
        let persistence = makePersistence()
        let store = RepoStore(persistence: persistence)
        // Scanner override returns zero discovered repos — tests that need
        // sidebar state drive it explicitly, but for refresh() we just need
        // the call to complete without scanning real disk.
        let sidebar = RepoSidebarModel(
            persistence: persistence,
            repoStore: store,
            rootsOverride: [],
            scanner: { _ in [] }
        )
        let toasts = ToastCenter()
        let progress = ProgressCenter()
        let networkOps = NetworkOps(toasts: toasts, progress: progress)
        let branchOps = BranchOps(toasts: toasts)
        let commands = AppCommands(
            store: store,
            networkOps: networkOps,
            branchOps: branchOps,
            sidebar: sidebar,
            toasts: toasts
        )
        return Harness(
            persistence: persistence,
            store: store,
            sidebar: sidebar,
            toasts: toasts,
            progress: progress,
            networkOps: networkOps,
            branchOps: branchOps,
            commands: commands
        )
    }

    // MARK: - Tests

    /// VAL-UI-003: ⌘R must re-fire the FSEvents-style observer tick on the
    /// focused repo so downstream panels reload. Assert `lastChangeAt`
    /// advanced after `refreshFocused()`.
    @Test("refreshFocused bumps focus.lastChangeAt", .timeLimit(.minutes(1)))
    func refreshBumpsFocusLastChangeAt() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        let harness = Self.makeHarness()
        harness.store.focus(on: fixture.repo)
        guard let focus = harness.store.focus else {
            Issue.record("expected focus to be set")
            return
        }
        defer { focus.shutdown() }

        let before = focus.lastChangeAt
        // A 10ms sleep guarantees the new Date() is observably distinct —
        // Date granularity on modern macOS is sub-ms but the test should
        // not race against same-tick resolution.
        try await Task.sleep(nanoseconds: 10_000_000)

        await harness.commands.refreshFocused()

        #expect(focus.lastChangeAt > before, "refreshFocused should bump focus.lastChangeAt")
    }

    /// VAL-UI-003 / VAL-NET-001: ⌘⇧F must drive `NetworkOps.fetch` against
    /// the focused repo. We assert observable side-effects: a success toast
    /// and a corresponding advance of `origin/main` after the author side
    /// pushes new commits.
    @Test("fetchFocused drives NetworkOps.fetch on the focused repo", .timeLimit(.minutes(1)))
    func fetchFocusedCallsNetworkOps() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        try Self.pushIncoming(commitCount: 1, into: fixture)

        let harness = Self.makeHarness()
        harness.store.focus(on: fixture.repo)
        defer { harness.store.focus?.shutdown() }

        let beforeRemote = try GitFixtureHelper.capture(
            ["rev-parse", "origin/main"],
            cwd: fixture.tracker
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        await harness.commands.fetchFocused()

        let afterRemote = try GitFixtureHelper.capture(
            ["rev-parse", "origin/main"],
            cwd: fixture.tracker
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(afterRemote != beforeRemote, "origin/main should advance after fetchFocused")
        #expect(harness.toasts.toasts.count == 1)
        let toast = try #require(harness.toasts.toasts.first)
        #expect(toast.kind == .success)
    }

    /// VAL-UI-003 / VAL-NET-002: ⌘⇧P must drive `NetworkOps.pullFFOnly`.
    /// Observable: HEAD advances after the author pushes new commits.
    @Test("pullFocused drives NetworkOps.pullFFOnly on the focused repo", .timeLimit(.minutes(1)))
    func pullFocusedCallsNetworkOps() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        try Self.pushIncoming(commitCount: 1, into: fixture)

        let harness = Self.makeHarness()
        harness.store.focus(on: fixture.repo)
        defer { harness.store.focus?.shutdown() }

        let beforeHead = try GitFixtureHelper.capture(
            ["rev-parse", "HEAD"],
            cwd: fixture.tracker
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        await harness.commands.pullFocused()

        let afterHead = try GitFixtureHelper.capture(
            ["rev-parse", "HEAD"],
            cwd: fixture.tracker
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(afterHead != beforeHead, "HEAD should advance after pullFocused")
        let successToast = harness.toasts.toasts.first { $0.kind == .success }
        #expect(successToast != nil, "pullFocused should enqueue a success toast")
    }

    /// VAL-UI-003 / VAL-NET-003: ⌘⇧K must drive `NetworkOps.push`. We
    /// observe success by asserting the bare remote's main ref advances to
    /// match the tracker's local HEAD after pushing an additional commit.
    @Test("pushFocused drives NetworkOps.push on the focused repo", .timeLimit(.minutes(1)))
    func pushFocusedCallsNetworkOps() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        // Make a local commit on tracker so there's something to push.
        try GitFixtureHelper.exec(
            ["commit", "--allow-empty", "-m", "tracker-local"],
            cwd: fixture.tracker
        )

        let harness = Self.makeHarness()
        harness.store.focus(on: fixture.repo)
        defer { harness.store.focus?.shutdown() }

        let localHead = try GitFixtureHelper.capture(
            ["rev-parse", "HEAD"],
            cwd: fixture.tracker
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        await harness.commands.pushFocused()

        let remoteMain = try GitFixtureHelper.capture(
            ["rev-parse", "main"],
            cwd: fixture.bare
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(remoteMain == localHead, "bare origin/main should match tracker HEAD after pushFocused")
        let successToast = harness.toasts.toasts.first { $0.kind == .success }
        #expect(successToast != nil, "pushFocused should enqueue a success toast")
    }

    /// VAL-UI-003 / VAL-BRANCHOP-001: ⌘⇧N bumps `newBranchRequest` so the
    /// toolbar's `NewBranchButton` opens the sheet. Guarded by focus state
    /// so a keypress with no repo selected is a no-op.
    @Test("openNewBranchSheet bumps newBranchRequest when a repo is focused")
    func openNewBranchSheetBumpsBinding() throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        let harness = Self.makeHarness()
        #expect(harness.commands.newBranchRequest == nil)

        // No focus → no bump.
        harness.commands.openNewBranchSheet()
        #expect(harness.commands.newBranchRequest == nil, "openNewBranchSheet must no-op when no focus")

        harness.store.focus(on: fixture.repo)
        defer { harness.store.focus?.shutdown() }

        harness.commands.openNewBranchSheet()
        let firstBump = harness.commands.newBranchRequest
        #expect(firstBump != nil, "openNewBranchSheet should bump newBranchRequest when focused")

        harness.commands.openNewBranchSheet()
        let secondBump = harness.commands.newBranchRequest
        #expect(secondBump != nil)
        #expect(firstBump != secondBump, "re-bumping must produce a new UUID so .onChange fires again")
    }

    /// VAL-UI-003: the menu's `.disabled(appCommands?.hasFocus != true)`
    /// clauses depend on `hasFocus` tracking the store's focus state.
    @Test("hasFocus reflects store.focus presence")
    func commandsDisabledWithoutFocus() throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        let harness = Self.makeHarness()
        #expect(harness.commands.hasFocus == false, "no repo focused → hasFocus false")

        harness.store.focus(on: fixture.repo)
        defer { harness.store.focus?.shutdown() }
        #expect(harness.commands.hasFocus == true, "repo focused → hasFocus true")

        harness.store.focus(on: nil)
        #expect(harness.commands.hasFocus == false, "focus cleared → hasFocus false")
    }

    /// No-focus invocations of the async actions return cleanly without
    /// raising toasts or crashing — the menu's `.disabled(...)` usually
    /// blocks this path, but the underlying service must still be safe
    /// against races between a focus swap and a mid-flight shortcut.
    @Test("async actions are no-ops without a focused repo")
    func asyncActionsNoOpWithoutFocus() async {
        let harness = Self.makeHarness()

        await harness.commands.fetchFocused()
        await harness.commands.pullFocused()
        await harness.commands.pushFocused()
        await harness.commands.refreshFocused()

        #expect(harness.toasts.toasts.isEmpty, "no-focus actions must not enqueue toasts")
    }
}
