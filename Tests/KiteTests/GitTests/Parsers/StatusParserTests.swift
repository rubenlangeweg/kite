import Foundation
import Testing
@testable import Kite

@Suite("StatusParser")
struct StatusParserTests {
    @Test("clean repo parses as isClean and branch 'main'")
    func cleanRepoParses() throws {
        let repo = GitFixtureHelper.tempURL()
        defer { GitFixtureHelper.cleanup(repo) }
        try GitFixtureHelper.cleanRepo(at: repo)

        let raw = try GitFixtureHelper.capture(
            ["status", "--porcelain=v2", "--branch", "-z"], cwd: repo
        )
        let summary = try StatusParser.parse(raw)
        #expect(summary.branch == "main")
        #expect(summary.detachedAt == nil)
        #expect(summary.upstream == nil)
        #expect(summary.ahead == 0)
        #expect(summary.behind == 0)
        #expect(summary.staged == 0)
        #expect(summary.modified == 0)
        #expect(summary.untracked == 0)
        #expect(summary.isClean)
    }

    @Test("mixed staged + modified + untracked produces correct counts")
    func mixedWorkingTree() throws {
        let repo = GitFixtureHelper.tempURL()
        defer { GitFixtureHelper.cleanup(repo) }
        try GitFixtureHelper.cleanRepo(at: repo)
        // Commit a tracked file we can then modify.
        try "v1".write(
            to: repo.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8
        )
        try GitFixtureHelper.exec(["add", "tracked.txt"], cwd: repo)
        try GitFixtureHelper.exec(["commit", "-m", "add tracked"], cwd: repo)

        // Now:
        // - tracked.txt is modified in both index (staged) and worktree.
        // - staged.txt is freshly added (staged only).
        // - untracked.txt exists and is untracked.
        try "v2-staged".write(
            to: repo.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8
        )
        try GitFixtureHelper.exec(["add", "tracked.txt"], cwd: repo)
        try "v3-worktree".write(
            to: repo.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8
        )
        try "new".write(
            to: repo.appendingPathComponent("staged.txt"), atomically: true, encoding: .utf8
        )
        try GitFixtureHelper.exec(["add", "staged.txt"], cwd: repo)
        try "idle".write(
            to: repo.appendingPathComponent("untracked.txt"), atomically: true, encoding: .utf8
        )

        let raw = try GitFixtureHelper.capture(
            ["status", "--porcelain=v2", "--branch", "-z"], cwd: repo
        )
        let summary = try StatusParser.parse(raw)
        #expect(summary.branch == "main")
        #expect(summary.staged >= 2, "expected at least tracked.txt and staged.txt staged")
        #expect(summary.modified >= 1, "expected tracked.txt worktree modification")
        #expect(summary.untracked == 1)
        #expect(!summary.isClean)
    }

    @Test("detached HEAD surfaces detachedAt short-sha and nil branch")
    func detachedHeadParses() throws {
        let repo = GitFixtureHelper.tempURL()
        defer { GitFixtureHelper.cleanup(repo) }
        try GitFixtureHelper.cleanRepo(at: repo)
        try "c2".write(
            to: repo.appendingPathComponent("x.txt"), atomically: true, encoding: .utf8
        )
        try GitFixtureHelper.exec(["add", "x.txt"], cwd: repo)
        try GitFixtureHelper.exec(["commit", "-m", "second"], cwd: repo)
        try GitFixtureHelper.exec(["switch", "--detach", "HEAD^"], cwd: repo)

        let raw = try GitFixtureHelper.capture(
            ["status", "--porcelain=v2", "--branch", "-z"], cwd: repo
        )
        let summary = try StatusParser.parse(raw)
        #expect(summary.branch == nil)
        let detached = try #require(summary.detachedAt)
        #expect(detached.count == 7)
    }

    @Test("no-upstream branch leaves upstream/ahead/behind at defaults")
    func noUpstreamParses() throws {
        let repo = GitFixtureHelper.tempURL()
        defer { GitFixtureHelper.cleanup(repo) }
        try GitFixtureHelper.cleanRepo(at: repo)

        let raw = try GitFixtureHelper.capture(
            ["status", "--porcelain=v2", "--branch", "-z"], cwd: repo
        )
        let summary = try StatusParser.parse(raw)
        #expect(summary.upstream == nil)
        #expect(summary.ahead == 0)
        #expect(summary.behind == 0)
    }

    @Test("empty input is handled as clean empty summary (does not throw)")
    func emptyInputDoesNotThrow() throws {
        let summary = try StatusParser.parse("")
        #expect(summary.branch == nil)
        #expect(summary.isClean)
    }

    @Test("synthetic branch.ab parses ahead/behind correctly")
    func aheadBehindHeader() throws {
        // Synthetic record — git emits these only when upstream is set; we
        // can't easily produce one without a real remote. Ensure our header
        // parser reads +N -M.
        let record = "# branch.oid abc\u{00}# branch.head main\u{00}# branch.upstream origin/main" +
            "\u{00}# branch.ab +3 -7\u{00}"
        let summary = try StatusParser.parse(record)
        #expect(summary.branch == "main")
        #expect(summary.upstream == "origin/main")
        #expect(summary.ahead == 3)
        #expect(summary.behind == 7)
    }
}
