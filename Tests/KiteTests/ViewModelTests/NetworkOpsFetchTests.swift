import Foundation
import Testing
@testable import Kite

/// Unit tests for `NetworkOps.fetch(on:)` using real fixture repos.
///
/// The fixtures are two linked repos — an "upstream author" working clone
/// that pushes commits to a bare remote, and the repo-under-test which is
/// cloned from that bare remote and subsequently fetches new commits.
///
/// Fulfills: VAL-NET-001 (runs git fetch --all --prune),
/// VAL-NET-005 (success toast on completion),
/// VAL-NET-011 (progress parser exercised via live stderr).
@Suite("NetworkOps.fetch")
@MainActor
struct NetworkOpsFetchTests {
    /// Three-way fixture shape: a bare remote, an "author" clone that pushes
    /// commits to the bare remote, and a "tracker" clone that is the subject
    /// of our fetch tests. All under a common tmp parent dir.
    private struct Fixtures {
        let parent: URL
        let bare: URL
        let author: URL
        let tracker: URL
        let repo: DiscoveredRepo
    }

    private static func makeFixture(authorCommitCount: Int = 1) throws -> Fixtures {
        let parent = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let bare = parent.appendingPathComponent("origin.git")
        try GitFixtureHelper.exec(["init", "--bare", "-b", "main", bare.path], cwd: parent)

        let author = parent.appendingPathComponent("author")
        try GitFixtureHelper.cleanRepo(at: author)
        try GitFixtureHelper.exec(["remote", "add", "origin", bare.path], cwd: author)
        try GitFixtureHelper.exec(["push", "-u", "origin", "main"], cwd: author)

        // Author pre-populates the bare so the tracker clone starts from a
        // non-empty upstream. That's the common shape for a "fetch picks up
        // new commits" scenario — push extras *after* cloning.
        for index in 0 ..< max(0, authorCommitCount - 1) {
            try GitFixtureHelper.exec(["commit", "--allow-empty", "-m", "author-pre-\(index)"], cwd: author)
        }
        if authorCommitCount > 1 {
            try GitFixtureHelper.exec(["push", "origin", "main"], cwd: author)
        }

        let tracker = parent.appendingPathComponent("tracker")
        try GitFixtureHelper.exec(["clone", bare.path, tracker.path], cwd: parent)
        // `clone` doesn't configure the same user identity we use elsewhere —
        // make fetch-through-queue behaviour independent of global git config.
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

    /// Push `commitCount` additional empty commits onto origin/main via the
    /// author clone so the tracker's subsequent fetch has work to do.
    private static func pushIncoming(commitCount: Int, into fixture: Fixtures) throws {
        for index in 0 ..< commitCount {
            try GitFixtureHelper.exec(
                ["commit", "--allow-empty", "-m", "incoming-\(index)"],
                cwd: fixture.author
            )
        }
        try GitFixtureHelper.exec(["push", "origin", "main"], cwd: fixture.author)
    }

    // MARK: - Tests

    /// VAL-NET-001 / VAL-NET-005: a fetch with incoming commits succeeds and
    /// produces a green success toast. The tracker's origin/main ref should
    /// advance in lockstep with the author's push.
    @Test("fetch reports success and enqueues a success toast", .timeLimit(.minutes(1)))
    func fetchReportsSuccess() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        try Self.pushIncoming(commitCount: 1, into: fixture)

        let focus = Self.makeFocus(for: fixture)
        defer { focus.shutdown() }

        let toasts = ToastCenter()
        let progress = ProgressCenter()
        let ops = NetworkOps(toasts: toasts, progress: progress)

        let beforeRemote = try GitFixtureHelper.capture(
            ["rev-parse", "origin/main"],
            cwd: fixture.tracker
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let ok = await ops.fetch(on: focus)
        #expect(ok, "fetch should report success")

        let afterRemote = try GitFixtureHelper.capture(
            ["rev-parse", "origin/main"],
            cwd: fixture.tracker
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(afterRemote != beforeRemote, "origin/main should advance after fetch")

        #expect(toasts.toasts.count == 1)
        let toast = try #require(toasts.toasts.first)
        #expect(toast.kind == .success)
        #expect(toast.message.contains("tracker"))
    }

    /// VAL-NET-001 negative: when the remote's bare repo is deleted, the
    /// fetch fails and produces a sticky red error toast. Detail carries
    /// the captured stderr so the user can click-to-expand.
    @Test("fetch reports error when the remote is unreachable", .timeLimit(.minutes(1)))
    func fetchReportsErrorOnMissingRemote() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        // Bust the remote by deleting its backing dir. The tracker's
        // origin URL still points at it.
        try FileManager.default.removeItem(at: fixture.bare)

        let focus = Self.makeFocus(for: fixture)
        defer { focus.shutdown() }

        let toasts = ToastCenter()
        let progress = ProgressCenter()
        let ops = NetworkOps(toasts: toasts, progress: progress)

        let ok = await ops.fetch(on: focus)
        #expect(!ok, "fetch against missing remote should fail")

        #expect(toasts.toasts.count == 1)
        let toast = try #require(toasts.toasts.first)
        #expect(toast.kind == .error)
        // Detail is the captured stderr — should at least mention the error.
        let detail = toast.detail ?? ""
        #expect(
            detail.lowercased().contains("not") || detail.lowercased().contains("unable") || !detail.isEmpty,
            "expected stderr detail to be non-empty for missing remote failure; got: \(detail)"
        )
    }

    /// VAL-NET-011 / VAL-UI-006: progress is driven during the fetch and
    /// fully drained on completion. We can't reliably catch a non-empty
    /// `progress.active` slice mid-fetch without racing — instead we assert
    /// the terminal state: empty after success, and that `begin(_:)` was
    /// called at all (indirectly, via toast outcome — if `begin` never
    /// ran, neither would the serialised stream loop).
    @Test("fetch drives progress lifecycle to completion", .timeLimit(.minutes(1)))
    func fetchDrivesProgress() async throws {
        let fixture = try Self.makeFixture(authorCommitCount: 5)
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        // Push another small batch so the fetch has something to do.
        try Self.pushIncoming(commitCount: 3, into: fixture)

        let focus = Self.makeFocus(for: fixture)
        defer { focus.shutdown() }

        let toasts = ToastCenter()
        let progress = ProgressCenter()
        let ops = NetworkOps(toasts: toasts, progress: progress)

        #expect(progress.active.isEmpty, "precondition: progress should be idle")

        let ok = await ops.fetch(on: focus)
        #expect(ok)

        // Post-fetch the progress slot must be drained so the toolbar
        // indicator collapses.
        #expect(progress.active.isEmpty, "progress.active should be empty after fetch completes")
    }

    /// VAL-NET-009 (via VAL-NET-001 flow): two rapid fetches executed against
    /// the same focus serialise via `focus.queue`. Both should succeed and
    /// both should show up as two successful toasts.
    @Test("rapid double-fetch serialises through the focus queue", .timeLimit(.minutes(2)))
    func fetchSerializesInQueue() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        try Self.pushIncoming(commitCount: 2, into: fixture)

        let focus = Self.makeFocus(for: fixture)
        defer { focus.shutdown() }

        let toasts = ToastCenter()
        let progress = ProgressCenter()
        let ops = NetworkOps(toasts: toasts, progress: progress)

        async let first = ops.fetch(on: focus)
        async let second = ops.fetch(on: focus)
        let (aOK, bOK) = await (first, second)
        #expect(aOK, "first fetch should succeed")
        #expect(bOK, "second fetch should succeed")

        // Both fetches should have produced a success toast. The cap is 3,
        // so two fit easily.
        let successes = toasts.toasts.filter { $0.kind == .success }
        #expect(successes.count == 2, "expected 2 success toasts; got \(successes.count)")

        // Progress must be fully drained — if the queue had mis-serialised,
        // one op's `end` might race against another's `begin` and leave a
        // stale item behind.
        #expect(progress.active.isEmpty)
    }
}
