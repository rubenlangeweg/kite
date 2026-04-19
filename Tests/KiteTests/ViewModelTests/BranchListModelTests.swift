import Foundation
import Testing
@testable import Kite

/// Unit tests for `BranchListModel` using real fixture repos (GitFixtureHelper).
///
/// Each test spins up one (or two) tmp-dir fixture repos, drives the model,
/// and asserts against parsed state. No mocking of `git`.
///
/// Fulfills: VAL-BRANCH-001, VAL-BRANCH-002, VAL-BRANCH-003, VAL-BRANCH-004.
@Suite("BranchListModel")
@MainActor
struct BranchListModelTests {
    /// Fixture shape: a "working" repo `origin`-tracking a bare remote.
    private struct Fixtures {
        let parent: URL
        let bare: URL
        let work: URL
        let repo: DiscoveredRepo
    }

    /// Build a fixture: a `remote.git` bare repo and a `work` checkout pushed
    /// to `origin`. Both live under a fresh tmp parent dir.
    private static func makeFixture() throws -> Fixtures {
        let parent = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let bare = parent.appendingPathComponent("remote.git")
        try GitFixtureHelper.exec(["init", "--bare", "-b", "main", bare.path], cwd: parent)

        let work = parent.appendingPathComponent("work")
        try GitFixtureHelper.cleanRepo(at: work)
        try GitFixtureHelper.exec(["remote", "add", "origin", bare.path], cwd: work)
        try GitFixtureHelper.exec(["push", "-u", "origin", "main"], cwd: work)

        let repo = DiscoveredRepo(
            url: work,
            displayName: "work",
            rootPath: parent,
            isBare: false
        )
        return Fixtures(parent: parent, bare: bare, work: work, repo: repo)
    }

    private static func makeFocus(for fixture: Fixtures) -> RepoFocus {
        RepoFocus(repo: fixture.repo)
    }

    // MARK: - VAL-BRANCH-001

    @Test("reload populates local branches with main as current")
    func reloadPopulatesLocalBranches() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        try GitFixtureHelper.exec(["branch", "feature/a"], cwd: fixture.work)
        try GitFixtureHelper.exec(["branch", "feature/b"], cwd: fixture.work)

        let focus = Self.makeFocus(for: fixture)
        defer { focus.shutdown() }

        let model = BranchListModel()
        await model.reload(for: focus)

        #expect(model.lastError == nil, "lastError: \(model.lastError ?? "?")")
        #expect(model.local.count == 3)
        let names = model.local.map(\.shortName).sorted()
        #expect(names == ["feature/a", "feature/b", "main"])
        let current = model.local.first { $0.isHead }
        #expect(current?.shortName == "main")
    }

    // MARK: - VAL-BRANCH-002

    @Test("reload groups remote branches by remote and filters HEAD pointer")
    func reloadPopulatesRemoteBranches() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        // Push a second branch to origin so we have two remote branches.
        try GitFixtureHelper.exec(["switch", "-c", "feature/x"], cwd: fixture.work)
        try GitFixtureHelper.exec(["commit", "--allow-empty", "-m", "x"], cwd: fixture.work)
        try GitFixtureHelper.exec(["push", "-u", "origin", "feature/x"], cwd: fixture.work)
        try GitFixtureHelper.exec(["switch", "main"], cwd: fixture.work)

        // Set origin/HEAD to exercise the HEAD-filter path.
        try GitFixtureHelper.exec(["remote", "set-head", "origin", "main"], cwd: fixture.work)

        let focus = Self.makeFocus(for: fixture)
        defer { focus.shutdown() }

        let model = BranchListModel()
        await model.reload(for: focus)

        #expect(model.lastError == nil)
        #expect(model.remote["origin"] != nil)
        let remoteNames = (model.remote["origin"] ?? []).map(\.shortName).sorted()
        #expect(remoteNames == ["origin/feature/x", "origin/main"])
        // origin/HEAD must not leak through.
        #expect(!remoteNames.contains("origin/HEAD"))
    }

    // MARK: - VAL-BRANCH-003

    @Test("reload detects ahead counts when local has unpushed commits")
    func reloadDetectsAheadBehind() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        // Make local commits past origin/main to produce ahead > 0.
        try GitFixtureHelper.exec(["commit", "--allow-empty", "-m", "extra-1"], cwd: fixture.work)
        try GitFixtureHelper.exec(["commit", "--allow-empty", "-m", "extra-2"], cwd: fixture.work)

        let focus = Self.makeFocus(for: fixture)
        defer { focus.shutdown() }

        let model = BranchListModel()
        await model.reload(for: focus)

        #expect(model.lastError == nil)
        let main = try #require(model.local.first { $0.shortName == "main" })
        #expect(main.upstream == "origin/main")
        #expect((main.ahead ?? 0) == 2)
        #expect((main.behind ?? 0) == 0)
        #expect(main.isGone == false)
    }

    @Test("reload surfaces isGone when upstream branch is deleted remotely")
    func reloadDetectsGoneUpstream() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        // Create + push a second branch, then delete it remotely, then fetch
        // with prune to mark the local's upstream as [gone].
        try GitFixtureHelper.exec(["switch", "-c", "feature/doomed"], cwd: fixture.work)
        try GitFixtureHelper.exec(["commit", "--allow-empty", "-m", "doomed"], cwd: fixture.work)
        try GitFixtureHelper.exec(["push", "-u", "origin", "feature/doomed"], cwd: fixture.work)
        try GitFixtureHelper.exec(["push", "origin", "--delete", "feature/doomed"], cwd: fixture.work)
        try GitFixtureHelper.exec(["fetch", "--prune"], cwd: fixture.work)

        let focus = Self.makeFocus(for: fixture)
        defer { focus.shutdown() }

        let model = BranchListModel()
        await model.reload(for: focus)

        #expect(model.lastError == nil)
        let doomed = try #require(model.local.first { $0.shortName == "feature/doomed" })
        #expect(doomed.isGone == true)
        #expect(doomed.upstream == "origin/feature/doomed")
    }

    // MARK: - VAL-BRANCH-004

    @Test("reload surfaces detached HEAD pseudo-row with short SHA")
    func reloadDetectsDetachedHead() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        // Need a second commit on main so we can detach to the previous one.
        try GitFixtureHelper.exec(["commit", "--allow-empty", "-m", "second"], cwd: fixture.work)
        try GitFixtureHelper.exec(["switch", "--detach", "HEAD^"], cwd: fixture.work)

        let focus = Self.makeFocus(for: fixture)
        defer { focus.shutdown() }

        let model = BranchListModel()
        await model.reload(for: focus)

        #expect(model.lastError == nil)
        let detached = try #require(model.detachedHead)
        // git's short-SHA prefix length is configurable; typical default is 7+.
        #expect(detached.shortSHA.count >= 4)
        #expect(!model.local.contains { $0.isHead })
    }

    // MARK: - Empty repo

    @Test("reload tolerates an empty repo with no commits")
    func reloadHandlesEmptyRepo() async throws {
        let parent = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { GitFixtureHelper.cleanup(parent) }

        let emptyURL = parent.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: emptyURL, withIntermediateDirectories: true)
        try GitFixtureHelper.exec(["init", "-b", "main"], cwd: emptyURL)
        // No commits; HEAD is unborn.

        let repo = DiscoveredRepo(url: emptyURL, displayName: "empty", rootPath: parent, isBare: false)
        let focus = RepoFocus(repo: repo)
        defer { focus.shutdown() }

        let model = BranchListModel()
        await model.reload(for: focus)

        #expect(model.lastError == nil)
        #expect(model.local.isEmpty)
        #expect(model.remote.isEmpty)
        #expect(model.detachedHead == nil)
    }
}
