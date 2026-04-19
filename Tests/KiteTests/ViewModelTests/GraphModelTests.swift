import Foundation
import Testing
@testable import Kite

/// Unit tests for `GraphModel` using real fixture repos (GitFixtureHelper).
///
/// Each test spins up one tmp-dir fixture, drives the model via
/// `reload(for:)`, and asserts against the parsed/enriched state. No mocking
/// of git — every call goes through `Git.run`.
///
/// Fulfills: VAL-GRAPH-009 (select routing), VAL-GRAPH-010 (state behind
/// List's stable-id scroll preservation), VAL-GRAPH-011 (shallow detection).
@Suite("GraphModel")
@MainActor
struct GraphModelTests {
    // MARK: - Fixture builders

    private struct Fixture {
        let parent: URL
        let repo: DiscoveredRepo
        let focus: RepoFocus
    }

    /// Build a fresh repo with a single `initial` commit on `main`.
    private static func makeStandalone() throws -> Fixture {
        let parent = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let work = parent.appendingPathComponent("work")
        try GitFixtureHelper.cleanRepo(at: work)
        let repo = DiscoveredRepo(url: work, displayName: "work", rootPath: parent, isBare: false)
        return Fixture(parent: parent, repo: repo, focus: RepoFocus(repo: repo))
    }

    /// Build a linear history of `count` commits — commit i on top of commit i-1.
    private static func appendLinearCommits(_ count: Int, cwd: URL) throws {
        for index in 0 ..< count {
            try GitFixtureHelper.exec(["commit", "--allow-empty", "-m", "commit-\(index)"], cwd: cwd)
        }
    }

    // MARK: - 1. VAL-GRAPH-001 (row population), VAL-GRAPH-010 (state for scroll)

    @Test("reload populates rows for a linear repo")
    func reloadPopulatesRowsForLinearRepo() async throws {
        let fixture = try Self.makeStandalone()
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }
        // 4 additional commits + 1 initial = 5.
        try Self.appendLinearCommits(4, cwd: fixture.focus.repo.url)

        let model = GraphModel()
        await model.reload(for: fixture.focus)

        #expect(model.lastError == nil, "lastError: \(model.lastError ?? "?")")
        #expect(model.rows.count == 5)
        // Linear → every row in lane 0.
        #expect(model.rows.allSatisfy { $0.column == 0 })
        #expect(model.commitLimitHit == false)
        #expect(model.isShallowRepo == false)
    }

    // MARK: - 2. VAL-GRAPH-007 / VAL-GRAPH-001 enrichment

    @Test("reload attaches refs to rows matching their tip commit")
    func reloadPopulatesRefs() async throws {
        let fixture = try Self.makeStandalone()
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        // Add a second commit, then a branch `feature-x` pointing at HEAD.
        try GitFixtureHelper.exec(
            ["commit", "--allow-empty", "-m", "second"],
            cwd: fixture.focus.repo.url
        )
        try GitFixtureHelper.exec(["branch", "feature-x"], cwd: fixture.focus.repo.url)

        let model = GraphModel()
        await model.reload(for: fixture.focus)

        #expect(model.lastError == nil)
        let tip = try #require(model.rows.first)
        let hasFeatureX = tip.refs.contains { ref in
            if case let .localBranch(name) = ref { return name == "feature-x" }
            return false
        }
        #expect(hasFeatureX, "feature-x should be attached to the tip row")
    }

    // MARK: - 3. HEAD enrichment

    @Test("reload detects current branch and prepends HEAD pill")
    func reloadDetectsCurrentBranch() async throws {
        let fixture = try Self.makeStandalone()
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        let model = GraphModel()
        await model.reload(for: fixture.focus)

        #expect(model.lastError == nil)
        let tip = try #require(model.rows.first)
        // GraphRowRefs prepends `.head` when currentBranch matches a
        // localBranch on the same commit.
        let hasHead = tip.refs.contains { ref in
            if case .head = ref { return true }
            return false
        }
        let hasMain = tip.refs.contains { ref in
            if case let .localBranch(name) = ref { return name == "main" }
            return false
        }
        #expect(hasHead, "tip row should carry a synthetic .head pill")
        #expect(hasMain, "tip row should still carry .localBranch(\"main\")")
    }

    // MARK: - 4. Detached HEAD

    @Test("reload on detached HEAD produces no .head pill anywhere")
    func reloadDetachedHeadHasNoHEADPill() async throws {
        let fixture = try Self.makeStandalone()
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        // Need a second commit so we can detach to HEAD^.
        try GitFixtureHelper.exec(
            ["commit", "--allow-empty", "-m", "second"],
            cwd: fixture.focus.repo.url
        )
        try GitFixtureHelper.exec(["switch", "--detach", "HEAD^"], cwd: fixture.focus.repo.url)

        let model = GraphModel()
        await model.reload(for: fixture.focus)

        #expect(model.lastError == nil)
        let anyHead = model.rows.flatMap(\.refs).contains { ref in
            if case .head = ref { return true }
            return false
        }
        #expect(anyHead == false, "detached HEAD must not surface a .head pill")
    }

    // MARK: - 5. VAL-GRAPH-011 shallow flag

    @Test("reload sets isShallowRepo when repo is a shallow clone")
    func reloadSetsShallowFlag() async throws {
        // 1) Build a "remote" with 5 linear commits.
        let parent = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { GitFixtureHelper.cleanup(parent) }

        let origin = parent.appendingPathComponent("origin")
        try GitFixtureHelper.cleanRepo(at: origin)
        try Self.appendLinearCommits(4, cwd: origin) // initial + 4 = 5 commits

        // 2) Clone with `--depth=1` into a new path — use file:// because local
        //    clones bypass shallow and print `warning: --depth is ignored in
        //    local clones; use file:// instead.` (observed on git 2.50.1).
        let shallow = parent.appendingPathComponent("shallow")
        try GitFixtureHelper.exec(
            ["clone", "--depth=1", "file://\(origin.path)", shallow.path],
            cwd: parent
        )

        let repo = DiscoveredRepo(url: shallow, displayName: "shallow", rootPath: parent, isBare: false)
        let focus = RepoFocus(repo: repo)
        defer { focus.shutdown() }

        let model = GraphModel()
        await model.reload(for: focus)

        #expect(model.lastError == nil)
        #expect(model.isShallowRepo == true, "shallow clone must surface the banner flag")
        // Shallow clone with --depth=1 produces a single visible commit.
        #expect(model.rows.count >= 1)
    }

    // MARK: - 6. VAL-GRAPH-001 commit cap

    @Test("reload flips commitLimitHit when history exceeds 200 commits")
    func reloadSetsCommitLimitHit() async throws {
        let fixture = try Self.makeStandalone()
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        // 200 more commits + 1 initial = 201; log caps at 200.
        try Self.appendLinearCommits(200, cwd: fixture.focus.repo.url)

        let model = GraphModel()
        await model.reload(for: fixture.focus)

        #expect(model.lastError == nil)
        #expect(model.rows.count == GraphModel.commitCap)
        #expect(model.commitLimitHit == true)
    }

    // MARK: - 7. Empty repo

    @Test("reload tolerates an empty repo with no commits")
    func reloadHandlesEmptyRepo() async throws {
        let parent = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { GitFixtureHelper.cleanup(parent) }

        let emptyURL = parent.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: emptyURL, withIntermediateDirectories: true)
        try GitFixtureHelper.exec(["init", "-b", "main"], cwd: emptyURL)
        // No commits — HEAD is unborn.

        let repo = DiscoveredRepo(url: emptyURL, displayName: "empty", rootPath: parent, isBare: false)
        let focus = RepoFocus(repo: repo)
        defer { focus.shutdown() }

        let model = GraphModel()
        await model.reload(for: focus)

        #expect(model.lastError == nil, "empty repo should not surface an error")
        #expect(model.rows.isEmpty)
        #expect(model.commitLimitHit == false)
        #expect(model.isShallowRepo == false)
    }

    // MARK: - 8. Error path — .git removed

    @Test("reload reports error when repo directory stops being a repo")
    func reloadReportsErrorOnInvalidRepo() async throws {
        let fixture = try Self.makeStandalone()
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        // Corrupt the fixture by deleting .git AFTER focus initialization.
        let gitDir = fixture.focus.repo.url.appendingPathComponent(".git")
        try FileManager.default.removeItem(at: gitDir)

        let model = GraphModel()
        await model.reload(for: fixture.focus)

        #expect(model.lastError != nil, "missing .git must surface lastError")
        #expect(model.rows.isEmpty)
    }

    // MARK: - 9. VAL-GRAPH-009 selection

    @Test("select(sha:) updates selectedSHA")
    func selectUpdatesState() {
        let model = GraphModel()
        #expect(model.selectedSHA == nil)

        model.select(sha: "abc1234")
        #expect(model.selectedSHA == "abc1234")

        model.select(sha: nil)
        #expect(model.selectedSHA == nil)
    }

    // MARK: - 10. clear() resets observable state

    @Test("clear() wipes rows and flags")
    func clearEmptiesState() async throws {
        let fixture = try Self.makeStandalone()
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        let model = GraphModel()
        await model.reload(for: fixture.focus)
        model.select(sha: "deadbeef")
        #expect(!model.rows.isEmpty)
        #expect(model.selectedSHA == "deadbeef")

        model.clear()
        #expect(model.rows.isEmpty)
        #expect(model.selectedSHA == nil)
        #expect(model.isShallowRepo == false)
        #expect(model.commitLimitHit == false)
        #expect(model.lastError == nil)
    }
}
