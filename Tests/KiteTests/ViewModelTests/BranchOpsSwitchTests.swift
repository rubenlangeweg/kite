import Foundation
import Testing
@testable import Kite

/// Unit tests for `BranchOps.switchToLocal(_:on:)` and
/// `BranchOps.switchToRemote(remote:branch:existingLocal:on:)` using real
/// fixture repos (GitFixtureHelper).
///
/// Fulfills:
///   - VAL-BRANCHOP-004 (`switchToLocal` moves HEAD)
///   - VAL-BRANCHOP-005 (`switchToRemote` creates tracking local / reuses
///     existing local when already tracking)
///   - VAL-BRANCHOP-006 (dirty-tree error surfaces documented toast)
@Suite("BranchOps.switch")
@MainActor
struct BranchOpsSwitchTests {
    // MARK: - Fixtures

    /// Plain local repo with two commits on `main` and nothing else.
    private struct LocalFixture {
        let parent: URL
        let repoURL: URL
        let repo: DiscoveredRepo
    }

    /// Bare "upstream" + working clone. Used for the switchToRemote flows so
    /// we have a real remote-tracking ref (`origin/<branch>`) to switch to.
    private struct RemoteFixture {
        let parent: URL
        let bare: URL
        let work: URL
        let repo: DiscoveredRepo
    }

    private static func makeLocalFixture() throws -> LocalFixture {
        let parent = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let repoURL = parent.appendingPathComponent("repo")
        try GitFixtureHelper.cleanRepo(at: repoURL)
        // Second commit so `switch -c` / cross-branch switches have real
        // HEAD to fork from.
        try GitFixtureHelper.exec(["commit", "--allow-empty", "-m", "second"], cwd: repoURL)
        let repo = DiscoveredRepo(
            url: repoURL,
            displayName: "repo",
            rootPath: parent,
            isBare: false
        )
        return LocalFixture(parent: parent, repoURL: repoURL, repo: repo)
    }

    /// Build a bare upstream with a `feature-x` branch alongside `main` and
    /// clone it so the working copy has `origin/main` + `origin/feature-x`
    /// remote-tracking refs but NO local `feature-x`.
    private static func makeRemoteFixture() throws -> RemoteFixture {
        let parent = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        // 1. Seed a working repo that we'll push to the bare upstream.
        let seed = parent.appendingPathComponent("seed")
        try GitFixtureHelper.cleanRepo(at: seed)
        try GitFixtureHelper.exec(["commit", "--allow-empty", "-m", "second"], cwd: seed)
        try GitFixtureHelper.exec(["branch", "feature-x"], cwd: seed)

        // 2. Bare upstream.
        let bare = parent.appendingPathComponent("remote.git")
        try GitFixtureHelper.exec(["init", "--bare", "-b", "main", bare.path], cwd: parent)

        // 3. Push both branches from the seed into bare.
        try GitFixtureHelper.exec(["remote", "add", "origin", bare.path], cwd: seed)
        try GitFixtureHelper.exec(["push", "origin", "main", "feature-x"], cwd: seed)

        // 4. Fresh clone — the "real" working repo the tests drive. This
        // mirrors a developer checking out a repo they didn't originally
        // create: only `main` exists locally; `origin/feature-x` is a
        // remote-tracking ref.
        let workParent = parent.appendingPathComponent("work-parent")
        try FileManager.default.createDirectory(at: workParent, withIntermediateDirectories: true)
        try GitFixtureHelper.exec(["clone", bare.path, "work"], cwd: workParent)
        let work = workParent.appendingPathComponent("work")
        // Standard identity config so future commits don't complain.
        try GitFixtureHelper.exec(["config", "user.email", "tests@kite.local"], cwd: work)
        try GitFixtureHelper.exec(["config", "user.name", "Kite Tests"], cwd: work)
        try GitFixtureHelper.exec(["config", "commit.gpgsign", "false"], cwd: work)

        let repo = DiscoveredRepo(
            url: work,
            displayName: "work",
            rootPath: workParent,
            isBare: false
        )
        return RemoteFixture(parent: parent, bare: bare, work: work, repo: repo)
    }

    private static func makeFocus(for repo: DiscoveredRepo) -> RepoFocus {
        RepoFocus(repo: repo)
    }

    // MARK: - Helpers

    private static func currentBranch(at url: URL) throws -> String? {
        let out = try GitFixtureHelper.capture(
            ["symbolic-ref", "--short", "HEAD"],
            cwd: url
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }

    private static func branchExists(_ name: String, at url: URL) throws -> Bool {
        let out = try GitFixtureHelper.capture(
            ["branch", "--list", name],
            cwd: url
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return !out.isEmpty
    }

    private static func localBranchCount(at url: URL) throws -> Int {
        let out = try GitFixtureHelper.capture(["branch", "--list"], cwd: url)
        return out
            .split(separator: "\n", omittingEmptySubsequences: true)
            .count
    }

    private static func upstreamOf(_ branch: String, at url: URL) throws -> String? {
        // Capture can't easily inspect the exit code; wrap in a try? to
        // accept the "no upstream" case (exit 1).
        let args = ["for-each-ref", "--format=%(upstream:short)", "refs/heads/\(branch)"]
        let out = try GitFixtureHelper.capture(args, cwd: url)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }

    // MARK: - VAL-BRANCHOP-004

    /// Success path: create `foo`, on `main`, call `switchToLocal("foo")` →
    /// HEAD points at `foo`, `lastError == nil`, one success toast.
    @Test("switchToLocal moves HEAD and posts a success toast", .timeLimit(.minutes(1)))
    func switchToLocalSuccess() async throws {
        let fixture = try Self.makeLocalFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        // Pre-create the target branch so switch (no -c) can find it.
        try GitFixtureHelper.exec(["branch", "foo"], cwd: fixture.repoURL)

        let focus = Self.makeFocus(for: fixture.repo)
        defer { focus.shutdown() }

        let toasts = ToastCenter()
        let ops = BranchOps(toasts: toasts)

        let ok = await ops.switchToLocal("foo", on: focus)
        #expect(ok, "switchToLocal should return true on success")
        #expect(try Self.currentBranch(at: fixture.repoURL) == "foo")

        let successes = toasts.toasts.filter { $0.kind == .success }
        #expect(successes.count == 1)
        #expect(successes.first?.message.contains("foo") == true)
    }

    /// Dirty-tree path: a tracked file has uncommitted changes that would be
    /// clobbered by switching to `other`; switchToLocal fails with the
    /// documented copy.
    @Test("switchToLocal dirty tree blocks switch with documented toast", .timeLimit(.minutes(1)))
    func switchToLocalDirtyTreeBlocks() async throws {
        let fixture = try Self.makeLocalFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        // Commit file.txt on main, branch to "other" with a different value,
        // come back, and leave an uncommitted clobber.
        let filePath = fixture.repoURL.appendingPathComponent("file.txt")
        try Data("v=main\n".utf8).write(to: filePath)
        try GitFixtureHelper.exec(["add", "file.txt"], cwd: fixture.repoURL)
        try GitFixtureHelper.exec(["commit", "-m", "main adds file"], cwd: fixture.repoURL)

        try GitFixtureHelper.exec(["checkout", "-b", "other"], cwd: fixture.repoURL)
        try Data("v=other\n".utf8).write(to: filePath)
        try GitFixtureHelper.exec(["add", "file.txt"], cwd: fixture.repoURL)
        try GitFixtureHelper.exec(["commit", "-m", "on other"], cwd: fixture.repoURL)

        try GitFixtureHelper.exec(["checkout", "main"], cwd: fixture.repoURL)
        try Data("v=main-dirty\n".utf8).write(to: filePath)

        let focus = Self.makeFocus(for: fixture.repo)
        defer { focus.shutdown() }

        let toasts = ToastCenter()
        let ops = BranchOps(toasts: toasts)

        let ok = await ops.switchToLocal("other", on: focus)
        #expect(!ok, "dirty tree must block switch")

        let errors = toasts.toasts.filter { $0.kind == .error }
        #expect(errors.count == 1)
        #expect(
            errors.first?.message == BranchOps.dirtyTreeMessage,
            "expected dirty-tree copy; got \(errors.first?.message ?? "<nil>")"
        )
        // HEAD stayed on main — dirty-tree failures never abandon the user
        // on an unexpected branch.
        #expect(try Self.currentBranch(at: fixture.repoURL) == "main")
    }

    /// Trying to switch to a non-existent branch surfaces a classified
    /// error and leaves HEAD where it was.
    @Test("switchToLocal to nonexistent branch surfaces error", .timeLimit(.minutes(1)))
    func switchToLocalNonExistentBranch() async throws {
        let fixture = try Self.makeLocalFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        let focus = Self.makeFocus(for: fixture.repo)
        defer { focus.shutdown() }

        let toasts = ToastCenter()
        let ops = BranchOps(toasts: toasts)

        let ok = await ops.switchToLocal("nonexistent", on: focus)
        #expect(!ok)
        #expect(try Self.currentBranch(at: fixture.repoURL) == "main")

        let errors = toasts.toasts.filter { $0.kind == .error }
        #expect(errors.count == 1)
    }

    // MARK: - VAL-BRANCHOP-005

    /// Clone fixture has `origin/feature-x` but no local `feature-x`.
    /// switchToRemote(existingLocal: nil) runs `git switch -c feature-x
    /// --track origin/feature-x`, the local branch now exists and tracks the
    /// remote.
    @Test("switchToRemote creates a tracking local when none exists", .timeLimit(.minutes(1)))
    func switchToRemoteCreatesTrackingLocal() async throws {
        let fixture = try Self.makeRemoteFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        // Sanity: the fresh clone has no local feature-x.
        #expect(try !(Self.branchExists("feature-x", at: fixture.work)))

        let focus = Self.makeFocus(for: fixture.repo)
        defer { focus.shutdown() }

        let toasts = ToastCenter()
        let ops = BranchOps(toasts: toasts)

        let ok = await ops.switchToRemote(
            remote: "origin",
            branch: "feature-x",
            existingLocal: nil,
            on: focus
        )
        #expect(ok, "switchToRemote should succeed on a fresh tracking create")

        #expect(try Self.branchExists("feature-x", at: fixture.work))
        #expect(try Self.currentBranch(at: fixture.work) == "feature-x")
        #expect(try Self.upstreamOf("feature-x", at: fixture.work) == "origin/feature-x")

        let successes = toasts.toasts.filter { $0.kind == .success }
        #expect(successes.count == 1)
        #expect(successes.first?.message.contains("feature-x") == true)
    }

    /// Reuse path: a local `feature-x` already tracks `origin/feature-x`
    /// (created by the first switchToRemote call). Switching away to main
    /// and calling switchToRemote again with `existingLocal: "feature-x"`
    /// must delegate to `switchToLocal` — so the local branch count doesn't
    /// grow and HEAD lands on the existing `feature-x`.
    @Test("switchToRemote reuses existing local when one already tracks", .timeLimit(.minutes(1)))
    func switchToRemoteReusesExistingLocal() async throws {
        let fixture = try Self.makeRemoteFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        let focus = Self.makeFocus(for: fixture.repo)
        defer { focus.shutdown() }

        let toasts = ToastCenter()
        let ops = BranchOps(toasts: toasts)

        // Prime: first create the tracking local.
        let primed = await ops.switchToRemote(
            remote: "origin",
            branch: "feature-x",
            existingLocal: nil,
            on: focus
        )
        #expect(primed)
        #expect(try Self.currentBranch(at: fixture.work) == "feature-x")

        let countAfterPrime = try Self.localBranchCount(at: fixture.work)

        // Switch away to main so the second call has somewhere to come from.
        try GitFixtureHelper.exec(["checkout", "main"], cwd: fixture.work)
        #expect(try Self.currentBranch(at: fixture.work) == "main")

        // Now call again with `existingLocal` set. Must reuse, not re-create.
        let reused = await ops.switchToRemote(
            remote: "origin",
            branch: "feature-x",
            existingLocal: "feature-x",
            on: focus
        )
        #expect(reused, "reuse path should succeed")
        #expect(try Self.currentBranch(at: fixture.work) == "feature-x")

        // Local branch count unchanged: we didn't spawn a second tracking
        // branch when the user re-double-clicked the remote ref.
        let countAfterReuse = try Self.localBranchCount(at: fixture.work)
        #expect(
            countAfterPrime == countAfterReuse,
            "local branch count grew: \(countAfterPrime) → \(countAfterReuse); reuse path created a duplicate"
        )
    }
}
