import Foundation
import Testing
@testable import Kite

/// Unit tests for `NetworkOps.pullFFOnly(on:)`, `NetworkOps.push(...)`,
/// and `NetworkOps.pushWithUpstream(...)`.
///
/// Each test provisions a three-way fixture: a bare origin, an "author"
/// clone that pushes incoming commits to the bare remote, and the
/// "tracker" clone which is the subject-under-test. Fixtures never touch
/// real user repos.
///
/// Fulfills: VAL-NET-002 (pull --ff-only + non-FF error),
/// VAL-NET-003 (push without --force, upstream-set),
/// VAL-NET-004 (auth failures route to toast),
/// VAL-SEC-001 (no --force in any args).
@Suite("NetworkOps.pullPush")
@MainActor
struct NetworkOpsPullPushTests {
    /// Three-way fixture shape mirroring `NetworkOpsFetchTests`: bare remote,
    /// author clone (pushes upstream commits), tracker clone (subject).
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

    private static func makeFocus(for fixture: Fixtures) -> RepoFocus {
        RepoFocus(repo: fixture.repo)
    }

    /// Push N empty commits through the author clone so the tracker sees
    /// incoming work on its subsequent fetch/pull.
    private static func pushIncoming(commitCount: Int, into fixture: Fixtures) throws {
        for index in 0 ..< commitCount {
            try GitFixtureHelper.exec(
                ["commit", "--allow-empty", "-m", "incoming-\(index)"],
                cwd: fixture.author
            )
        }
        try GitFixtureHelper.exec(["push", "origin", "main"], cwd: fixture.author)
    }

    // MARK: - Pull tests

    /// VAL-NET-002: `git pull --ff-only` advances HEAD when the remote has
    /// strictly-newer commits, producing a success toast.
    @Test("pullFFOnly applies clean fast-forward", .timeLimit(.minutes(1)))
    func pullFFOnlyAppliesCleanFetch() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        try Self.pushIncoming(commitCount: 2, into: fixture)

        let focus = Self.makeFocus(for: fixture)
        defer { focus.shutdown() }

        let toasts = ToastCenter()
        let progress = ProgressCenter()
        let ops = NetworkOps(toasts: toasts, progress: progress)

        let beforeHead = try GitFixtureHelper.capture(
            ["rev-parse", "HEAD"],
            cwd: fixture.tracker
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let ok = await ops.pullFFOnly(on: focus)
        #expect(ok, "pull should report success")

        let afterHead = try GitFixtureHelper.capture(
            ["rev-parse", "HEAD"],
            cwd: fixture.tracker
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(afterHead != beforeHead, "HEAD should advance after fast-forward pull")

        let success = toasts.toasts.first { $0.kind == .success }
        #expect(success != nil, "expected a success toast on clean pull")
    }

    /// VAL-NET-002 negative: pull on diverged history fails because the
    /// tracker has a local commit not present on the remote. Expect a
    /// sticky error toast with actionable non-fast-forward messaging.
    @Test("pullFFOnly fails on diverged history with non-FF toast", .timeLimit(.minutes(1)))
    func pullFFOnlyFailsOnDivergedHistory() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        // Author pushes a commit…
        try Self.pushIncoming(commitCount: 1, into: fixture)
        // …and the tracker makes a local commit on a stale base, diverging
        // its history from origin/main.
        try GitFixtureHelper.exec(["fetch", "origin"], cwd: fixture.tracker)
        // Reset the tracker's main back to its ORIG_HEAD equivalent so the
        // local commit we're about to make doesn't include origin's latest.
        // We sidestep `reset --hard` (VAL-SEC-002) by re-cloning into a
        // parallel branch with a single local commit. Simpler: make the
        // local commit BEFORE the fetch so HEAD is behind origin.
        let trackerHeadBeforeLocal = try GitFixtureHelper.capture(
            ["rev-parse", "HEAD"],
            cwd: fixture.tracker
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!trackerHeadBeforeLocal.isEmpty)

        // Rewind tracker main to its pre-fetch position by checking out that
        // sha and re-pointing main at it via branch --force. We avoid
        // `reset --hard` entirely.
        try GitFixtureHelper.exec(
            ["update-ref", "refs/heads/main", trackerHeadBeforeLocal],
            cwd: fixture.tracker
        )
        try GitFixtureHelper.exec(["switch", "main"], cwd: fixture.tracker)

        try GitFixtureHelper.exec(
            ["commit", "--allow-empty", "-m", "tracker-local-1"],
            cwd: fixture.tracker
        )
        try GitFixtureHelper.exec(
            ["commit", "--allow-empty", "-m", "tracker-local-2"],
            cwd: fixture.tracker
        )
        // Now tracker main has 2 local-only commits AND origin/main has an
        // extra author commit that tracker doesn't share — a true divergence.

        let focus = Self.makeFocus(for: fixture)
        defer { focus.shutdown() }

        let toasts = ToastCenter()
        let progress = ProgressCenter()
        let ops = NetworkOps(toasts: toasts, progress: progress)

        let ok = await ops.pullFFOnly(on: focus)
        #expect(!ok, "pull against diverged history must fail")

        let errors = toasts.toasts.filter { $0.kind == .error }
        #expect(errors.count == 1, "expected one sticky error toast; got \(errors.count)")
        let toast = try #require(errors.first)
        let lower = toast.message.lowercased()
        #expect(
            lower.contains("non-fast-forward") || lower.contains("fast-forward"),
            "error toast should mention non-fast-forward; got: \(toast.message)"
        )
    }

    // MARK: - Push tests

    /// VAL-NET-003: push on a tracked branch succeeds.
    @Test("push succeeds when branch is tracked", .timeLimit(.minutes(1)))
    func pushSucceedsWhenTracked() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        // Make a local commit on tracker main, which is already tracking
        // origin/main from clone. Push should succeed.
        try GitFixtureHelper.exec(
            ["commit", "--allow-empty", "-m", "tracker-local"],
            cwd: fixture.tracker
        )

        let focus = Self.makeFocus(for: fixture)
        defer { focus.shutdown() }

        let toasts = ToastCenter()
        let progress = ProgressCenter()
        let ops = NetworkOps(toasts: toasts, progress: progress)

        let outcome = await ops.push(on: focus, currentBranch: "main")
        #expect(outcome == .success, "expected success push outcome; got \(outcome)")

        let successes = toasts.toasts.filter { $0.kind == .success }
        #expect(successes.count == 1, "expected one success toast")

        // Origin bare should now reference the new head.
        let remoteHead = try GitFixtureHelper.capture(
            ["rev-parse", "refs/heads/main"],
            cwd: fixture.bare
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let trackerHead = try GitFixtureHelper.capture(
            ["rev-parse", "HEAD"],
            cwd: fixture.tracker
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(remoteHead == trackerHead, "origin main should match tracker HEAD after push")
    }

    /// VAL-NET-003: pushing a brand new unpublished branch reports
    /// `.needsUpstream(branch:remote:)` — does NOT toast.
    @Test("push reports needsUpstream when branch has no upstream", .timeLimit(.minutes(1)))
    func pushDetectsMissingUpstream() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        // Create a fresh branch locally — never pushed, no upstream.
        try GitFixtureHelper.exec(["switch", "-c", "feature-x"], cwd: fixture.tracker)
        try GitFixtureHelper.exec(
            ["commit", "--allow-empty", "-m", "feature commit"],
            cwd: fixture.tracker
        )

        let focus = Self.makeFocus(for: fixture)
        defer { focus.shutdown() }

        let toasts = ToastCenter()
        let progress = ProgressCenter()
        let ops = NetworkOps(toasts: toasts, progress: progress)

        let outcome = await ops.push(on: focus, currentBranch: "feature-x")
        #expect(
            outcome == .needsUpstream(branch: "feature-x", remote: "origin"),
            "expected needsUpstream outcome for fresh branch; got \(outcome)"
        )

        // Crucially: no error toast — the UI will present the set-upstream
        // sheet instead.
        let errors = toasts.toasts.filter { $0.kind == .error }
        #expect(errors.isEmpty, "needsUpstream must not raise an error toast; got \(errors)")
    }

    /// VAL-NET-003: `pushWithUpstream` actually wires up the tracking
    /// reference — after the call, `branch.<name>.remote` is `origin` and
    /// remote ref exists.
    @Test("pushWithUpstream sets the tracking ref", .timeLimit(.minutes(1)))
    func pushWithUpstreamSets() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        try GitFixtureHelper.exec(["switch", "-c", "feature-y"], cwd: fixture.tracker)
        try GitFixtureHelper.exec(
            ["commit", "--allow-empty", "-m", "feature-y"],
            cwd: fixture.tracker
        )

        let focus = Self.makeFocus(for: fixture)
        defer { focus.shutdown() }

        let toasts = ToastCenter()
        let progress = ProgressCenter()
        let ops = NetworkOps(toasts: toasts, progress: progress)

        let ok = await ops.pushWithUpstream(on: focus, branch: "feature-y", remote: "origin")
        #expect(ok, "pushWithUpstream should succeed")

        let tracked = try GitFixtureHelper.capture(
            ["config", "--get", "branch.feature-y.remote"],
            cwd: fixture.tracker
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(tracked == "origin", "expected branch.feature-y.remote=origin; got '\(tracked)'")

        // And the bare remote should now carry the new branch.
        let remoteSha = try GitFixtureHelper.capture(
            ["rev-parse", "refs/heads/feature-y"],
            cwd: fixture.bare
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!remoteSha.isEmpty, "origin should expose refs/heads/feature-y after upstream push")
    }

    /// VAL-SEC-001 / VAL-NET-003: set up a non-fast-forward state and verify
    /// that `push` fails WITHOUT advancing the remote head. If any `--force`
    /// flag slipped in, the push would succeed and the bare remote's head
    /// would change — this test catches that regression at runtime.
    @Test("push does not force on non-fast-forward", .timeLimit(.minutes(1)))
    func pushDoesNotForce() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        // Author pushes some extra commits onto origin/main to create a
        // position tracker doesn't share.
        try Self.pushIncoming(commitCount: 2, into: fixture)

        // Tracker makes a local commit on the stale base (no fetch).
        try GitFixtureHelper.exec(
            ["commit", "--allow-empty", "-m", "tracker-stale"],
            cwd: fixture.tracker
        )

        // Snapshot the remote head BEFORE we attempt the push.
        let bareBefore = try GitFixtureHelper.capture(
            ["rev-parse", "refs/heads/main"],
            cwd: fixture.bare
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let focus = Self.makeFocus(for: fixture)
        defer { focus.shutdown() }

        let toasts = ToastCenter()
        let progress = ProgressCenter()
        let ops = NetworkOps(toasts: toasts, progress: progress)

        let outcome = await ops.push(on: focus, currentBranch: "main")
        #expect(outcome == .failed, "non-FF push must fail; got \(outcome)")

        // Remote must be untouched — this is the load-bearing assertion of
        // this test.
        let bareAfter = try GitFixtureHelper.capture(
            ["rev-parse", "refs/heads/main"],
            cwd: fixture.bare
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(bareAfter == bareBefore, "origin main must NOT advance on a failed push")

        // And the UI surfaced an error toast.
        let errors = toasts.toasts.filter { $0.kind == .error }
        #expect(errors.count == 1, "expected one sticky error toast; got \(errors.count)")
    }
}
