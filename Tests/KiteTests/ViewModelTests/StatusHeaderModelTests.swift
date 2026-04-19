import Foundation
import Testing
@testable import Kite

/// Unit tests for `StatusHeaderModel` using real fixture repos (GitFixtureHelper).
///
/// Each test builds a tmp-dir fixture shaped to exercise one axis of
/// `git status --porcelain=v2 --branch -z` output, drives `reload(for:)`,
/// and asserts against the parsed summary. No mocking of `git`.
///
/// Fulfills: VAL-BRANCH-005 (working-tree summary), with ancillary coverage
/// of the parser-integrated ahead/behind path exercised end-to-end.
@Suite("StatusHeaderModel")
@MainActor
struct StatusHeaderModelTests {
    // MARK: - Fixture helpers

    private struct WorkFixture {
        let parent: URL
        let work: URL
        let focus: RepoFocus
    }

    /// A standalone repo with a single commit. No remote.
    private static func makeStandaloneFixture() throws -> WorkFixture {
        let parent = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let work = parent.appendingPathComponent("work")
        try GitFixtureHelper.cleanRepo(at: work)
        let repo = DiscoveredRepo(url: work, displayName: "work", rootPath: parent, isBare: false)
        return WorkFixture(parent: parent, work: work, focus: RepoFocus(repo: repo))
    }

    /// A working repo with an origin bare remote that tracks `main`.
    private static func makeTrackingFixture() throws -> WorkFixture {
        let parent = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let bare = parent.appendingPathComponent("remote.git")
        try GitFixtureHelper.exec(["init", "--bare", "-b", "main", bare.path], cwd: parent)

        let work = parent.appendingPathComponent("work")
        try GitFixtureHelper.cleanRepo(at: work)
        try GitFixtureHelper.exec(["remote", "add", "origin", bare.path], cwd: work)
        try GitFixtureHelper.exec(["push", "-u", "origin", "main"], cwd: work)

        let repo = DiscoveredRepo(url: work, displayName: "work", rootPath: parent, isBare: false)
        return WorkFixture(parent: parent, work: work, focus: RepoFocus(repo: repo))
    }

    // MARK: - Tests

    @Test("clean working tree produces isClean summary with current branch")
    func cleanTree() async throws {
        let fixture = try Self.makeStandaloneFixture()
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        let model = StatusHeaderModel()
        await model.reload(for: fixture.focus)

        let summary = try #require(model.summary)
        #expect(model.lastError == nil)
        #expect(summary.isClean)
        #expect(summary.branch == "main")
        #expect(summary.staged == 0)
        #expect(summary.modified == 0)
        #expect(summary.untracked == 0)
    }

    @Test("staged change (git add, not committed) produces staged == 1")
    func stagedChanges() async throws {
        let fixture = try Self.makeStandaloneFixture()
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        try "hello".write(
            to: fixture.work.appendingPathComponent("new.txt"),
            atomically: true, encoding: .utf8
        )
        try GitFixtureHelper.exec(["add", "new.txt"], cwd: fixture.work)

        let model = StatusHeaderModel()
        await model.reload(for: fixture.focus)

        let summary = try #require(model.summary)
        #expect(model.lastError == nil)
        #expect(summary.staged == 1)
        #expect(summary.modified == 0)
        #expect(summary.untracked == 0)
    }

    @Test("modified-not-staged produces modified == 1, staged == 0")
    func modifiedNotStaged() async throws {
        let fixture = try Self.makeStandaloneFixture()
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        let file = fixture.work.appendingPathComponent("tracked.txt")
        try "v1".write(to: file, atomically: true, encoding: .utf8)
        try GitFixtureHelper.exec(["add", "tracked.txt"], cwd: fixture.work)
        try GitFixtureHelper.exec(["commit", "-m", "add tracked"], cwd: fixture.work)

        // Modify the file in the worktree but do NOT stage it.
        try "v2-worktree".write(to: file, atomically: true, encoding: .utf8)

        let model = StatusHeaderModel()
        await model.reload(for: fixture.focus)

        let summary = try #require(model.summary)
        #expect(model.lastError == nil)
        #expect(summary.staged == 0)
        #expect(summary.modified == 1)
        #expect(summary.untracked == 0)
    }

    @Test("untracked file produces untracked == 1")
    func testUntracked() async throws {
        let fixture = try Self.makeStandaloneFixture()
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        try "hello".write(
            to: fixture.work.appendingPathComponent("free.txt"),
            atomically: true, encoding: .utf8
        )

        let model = StatusHeaderModel()
        await model.reload(for: fixture.focus)

        let summary = try #require(model.summary)
        #expect(model.lastError == nil)
        #expect(summary.staged == 0)
        #expect(summary.modified == 0)
        #expect(summary.untracked == 1)
    }

    @Test("mixed staged + modified + untracked all counted")
    func mixed() async throws {
        let fixture = try Self.makeStandaloneFixture()
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        // Pre-commit a tracked file so we have something to modify.
        let tracked = fixture.work.appendingPathComponent("tracked.txt")
        try "v1".write(to: tracked, atomically: true, encoding: .utf8)
        try GitFixtureHelper.exec(["add", "tracked.txt"], cwd: fixture.work)
        try GitFixtureHelper.exec(["commit", "-m", "add tracked"], cwd: fixture.work)

        // 1 staged-only: a new file, `git add`ed.
        try "new".write(
            to: fixture.work.appendingPathComponent("staged.txt"),
            atomically: true, encoding: .utf8
        )
        try GitFixtureHelper.exec(["add", "staged.txt"], cwd: fixture.work)

        // 1 modified-only: modify tracked in worktree, don't stage.
        try "v2-worktree".write(to: tracked, atomically: true, encoding: .utf8)

        // 1 untracked.
        try "idle".write(
            to: fixture.work.appendingPathComponent("untracked.txt"),
            atomically: true, encoding: .utf8
        )

        let model = StatusHeaderModel()
        await model.reload(for: fixture.focus)

        let summary = try #require(model.summary)
        #expect(model.lastError == nil)
        #expect(summary.staged == 1, "expected 1 staged; got \(summary.staged)")
        #expect(summary.modified == 1, "expected 1 modified; got \(summary.modified)")
        #expect(summary.untracked == 1, "expected 1 untracked; got \(summary.untracked)")
        #expect(!summary.isClean)
    }

    @Test("detached HEAD produces nil branch + non-nil detachedAt short sha")
    func detachedHead() async throws {
        let fixture = try Self.makeStandaloneFixture()
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        // Need a second commit so we can detach to HEAD^.
        try GitFixtureHelper.exec(["commit", "--allow-empty", "-m", "second"], cwd: fixture.work)
        try GitFixtureHelper.exec(["switch", "--detach", "HEAD^"], cwd: fixture.work)

        let model = StatusHeaderModel()
        await model.reload(for: fixture.focus)

        let summary = try #require(model.summary)
        #expect(model.lastError == nil)
        #expect(summary.branch == nil)
        let detached = try #require(summary.detachedAt)
        #expect(detached.count >= 4, "expected short SHA of at least 4 chars; got '\(detached)'")
    }

    @Test("diverged upstream produces ahead > 0 AND behind > 0")
    func aheadBehind() async throws {
        // Build a tracking fixture, branch the remote forward while the local
        // also advances. After `fetch` the local main is `ahead 1, behind 1`
        // of origin/main.
        let fixture = try Self.makeTrackingFixture()
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        // Clone the bare remote into a second workdir and push an extra
        // commit from there, so origin/main moves forward independently.
        let other = fixture.parent.appendingPathComponent("other")
        try GitFixtureHelper.exec(
            ["clone", fixture.parent.appendingPathComponent("remote.git").path, other.path],
            cwd: fixture.parent
        )
        try GitFixtureHelper.exec(["config", "user.email", "o@kite.local"], cwd: other)
        try GitFixtureHelper.exec(["config", "user.name", "Other"], cwd: other)
        try GitFixtureHelper.exec(["config", "commit.gpgsign", "false"], cwd: other)
        try GitFixtureHelper.exec(["commit", "--allow-empty", "-m", "remote-extra"], cwd: other)
        try GitFixtureHelper.exec(["push", "origin", "main"], cwd: other)

        // Meanwhile, the work repo also advances its local main.
        try GitFixtureHelper.exec(
            ["commit", "--allow-empty", "-m", "local-extra"], cwd: fixture.work
        )

        // Fetch so origin/main updates locally and branch.ab surfaces divergence.
        try GitFixtureHelper.exec(["fetch", "origin"], cwd: fixture.work)

        let model = StatusHeaderModel()
        await model.reload(for: fixture.focus)

        let summary = try #require(model.summary)
        #expect(model.lastError == nil)
        #expect(summary.branch == "main")
        #expect(summary.upstream == "origin/main")
        #expect(summary.ahead == 1, "expected ahead == 1; got \(summary.ahead)")
        #expect(summary.behind == 1, "expected behind == 1; got \(summary.behind)")
    }
}
