import Foundation
import Testing
@testable import Kite

/// Unit tests for `AutoFetchController` using real fixture repos with a
/// short interval override (≤1s) so the timer can be observed in the
/// test window.
///
/// We check "did a fetch fire?" indirectly by inspecting the tracker repo's
/// `origin/main` ref after pushing a new upstream commit — a successful
/// auto-fetch advances the ref. This avoids instrumenting `NetworkOps` for
/// test-only counters.
///
/// Fulfills: VAL-NET-006 (auto-fetch every interval on focused repo),
/// VAL-NET-007 (non-focused repos never fetched in background).
@Suite("AutoFetchController")
@MainActor
struct AutoFetchControllerTests {
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

    private static func revParse(_ ref: String, cwd: URL) throws -> String {
        try GitFixtureHelper.capture(["rev-parse", ref], cwd: cwd)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Use an isolated `UserDefaults` so we never step on real prefs.
    private static func makePersistence() -> PersistenceStore {
        let suite = "nl.rb2.kite.tests.autofetch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return PersistenceStore(defaults: defaults)
    }

    /// Wait up to `timeoutSeconds` for `condition` to return true, polling every
    /// 50ms. Returns true on satisfaction, false on timeout.
    private static func waitUntil(
        timeoutSeconds: Double,
        _ condition: () throws -> Bool
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if try condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return try condition()
    }

    // MARK: - Tests

    /// Passing a nil focus does nothing — no task spawned, no fetch fired.
    @Test("retarget(nil) stops the timer and schedules no fetch", .timeLimit(.minutes(1)))
    func stopsWhenNoFocus() async {
        let persistence = Self.makePersistence()
        let toasts = ToastCenter()
        let progress = ProgressCenter()
        let ops = NetworkOps(toasts: toasts, progress: progress)
        let controller = AutoFetchController(ops: ops, persistence: persistence)
        controller.intervalSeconds = 1

        controller.retarget(to: nil)
        #expect(!controller.isRunning, "No task should be spawned for nil focus")

        // Sleep past the interval to prove nothing fires.
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        #expect(toasts.toasts.isEmpty, "No fetches should fire for nil focus")
        #expect(!controller.isRunning)
    }

    /// With a focus and the toggle on, the timer fires an auto-fetch after
    /// the configured interval — the tracker's origin/main advances in
    /// lockstep with the author push.
    @Test("starts timer on focus and fires a fetch after the interval", .timeLimit(.minutes(2)))
    func startsTimerWhenFocused() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        let focus = RepoFocus(repo: fixture.repo)
        defer { focus.shutdown() }

        let persistence = Self.makePersistence()
        #expect(persistence.settings.autoFetchEnabled, "default toggle should be on")

        let toasts = ToastCenter()
        let progress = ProgressCenter()
        let ops = NetworkOps(toasts: toasts, progress: progress)
        let controller = AutoFetchController(ops: ops, persistence: persistence)
        controller.intervalSeconds = 1

        try Self.pushIncoming(commitCount: 1, into: fixture)
        let before = try Self.revParse("origin/main", cwd: fixture.tracker)

        controller.retarget(to: focus)
        #expect(controller.isRunning, "Task should be scheduled after retarget")

        // Wait up to 5s for origin/main to advance via the auto-fetch tick.
        let advanced = try await Self.waitUntil(timeoutSeconds: 5) {
            let current = try Self.revParse("origin/main", cwd: fixture.tracker)
            return current != before
        }
        #expect(advanced, "Expected origin/main to advance via auto-fetch within the interval window")

        controller.stop()
    }

    /// Retargeting from focus1 → focus2 before the first tick fires cancels
    /// the first task. The first repo's origin/main must stay put even
    /// though we pushed new upstream commits to it.
    @Test("retarget swap cancels the prior task", .timeLimit(.minutes(2)))
    func cancelsOnFocusChange() async throws {
        let fixtureA = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixtureA.parent) }
        let fixtureB = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixtureB.parent) }

        let focusA = RepoFocus(repo: fixtureA.repo)
        defer { focusA.shutdown() }
        let focusB = RepoFocus(repo: fixtureB.repo)
        defer { focusB.shutdown() }

        let persistence = Self.makePersistence()
        let toasts = ToastCenter()
        let progress = ProgressCenter()
        let ops = NetworkOps(toasts: toasts, progress: progress)
        let controller = AutoFetchController(ops: ops, persistence: persistence)
        controller.intervalSeconds = 1

        // Push incoming on A so that if an auto-fetch for A *did* fire, we'd
        // observe origin/main advance. We want to prove it does NOT advance.
        try Self.pushIncoming(commitCount: 1, into: fixtureA)
        let aBefore = try Self.revParse("origin/main", cwd: fixtureA.tracker)

        controller.retarget(to: focusA)
        // Immediately swap to B — the A task must be cancelled before its
        // first tick.
        controller.retarget(to: focusB)
        #expect(controller.isRunning)

        // Wait longer than the interval — A's ref must not have moved.
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        let aAfter = try Self.revParse("origin/main", cwd: fixtureA.tracker)
        #expect(aAfter == aBefore, "focusA's origin/main must not advance after swap to focusB")

        controller.stop()
    }

    /// Toggle off before retarget → no task spawned at all.
    @Test("respects disabled toggle at retarget time", .timeLimit(.minutes(1)))
    func respectsDisabledToggle() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        let focus = RepoFocus(repo: fixture.repo)
        defer { focus.shutdown() }

        let persistence = Self.makePersistence()
        persistence.setAutoFetchEnabled(false)

        let toasts = ToastCenter()
        let progress = ProgressCenter()
        let ops = NetworkOps(toasts: toasts, progress: progress)
        let controller = AutoFetchController(ops: ops, persistence: persistence)
        controller.intervalSeconds = 1

        try Self.pushIncoming(commitCount: 1, into: fixture)
        let before = try Self.revParse("origin/main", cwd: fixture.tracker)

        controller.retarget(to: focus)
        #expect(!controller.isRunning, "Disabled toggle should prevent task spawn")

        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let after = try Self.revParse("origin/main", cwd: fixture.tracker)
        #expect(after == before, "No fetch should fire while auto-fetch disabled")
        #expect(toasts.toasts.isEmpty)
    }

    /// Disabled → enabled + retarget wires the timer back up and fetches fire.
    @Test("re-enabling the toggle + retarget re-arms the timer", .timeLimit(.minutes(2)))
    func reactsToToggleEnable() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        let focus = RepoFocus(repo: fixture.repo)
        defer { focus.shutdown() }

        let persistence = Self.makePersistence()
        persistence.setAutoFetchEnabled(false)

        let toasts = ToastCenter()
        let progress = ProgressCenter()
        let ops = NetworkOps(toasts: toasts, progress: progress)
        let controller = AutoFetchController(ops: ops, persistence: persistence)
        controller.intervalSeconds = 1

        controller.retarget(to: focus)
        #expect(!controller.isRunning, "precondition: toggle off → no task")

        try Self.pushIncoming(commitCount: 1, into: fixture)
        let before = try Self.revParse("origin/main", cwd: fixture.tracker)

        persistence.setAutoFetchEnabled(true)
        controller.retarget(to: focus)
        #expect(controller.isRunning, "toggle on + retarget should schedule the task")

        let advanced = try await Self.waitUntil(timeoutSeconds: 5) {
            let current = try Self.revParse("origin/main", cwd: fixture.tracker)
            return current != before
        }
        #expect(advanced, "Expected origin/main to advance after re-enabling + retarget")

        controller.stop()
    }

    /// `stop()` tears down a running timer and leaves `isRunning` false.
    @Test("stop() hard-cancels the task", .timeLimit(.minutes(1)))
    func stopHardStops() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        let focus = RepoFocus(repo: fixture.repo)
        defer { focus.shutdown() }

        let persistence = Self.makePersistence()
        let toasts = ToastCenter()
        let progress = ProgressCenter()
        let ops = NetworkOps(toasts: toasts, progress: progress)
        let controller = AutoFetchController(ops: ops, persistence: persistence)
        controller.intervalSeconds = 1

        try Self.pushIncoming(commitCount: 1, into: fixture)
        let before = try Self.revParse("origin/main", cwd: fixture.tracker)

        controller.retarget(to: focus)
        #expect(controller.isRunning)

        controller.stop()
        #expect(!controller.isRunning, "stop() should leave isRunning=false")

        // Wait past the interval — nothing should fire.
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let after = try Self.revParse("origin/main", cwd: fixture.tracker)
        #expect(after == before, "No fetch should fire after stop()")
        #expect(toasts.toasts.isEmpty)
    }
}
