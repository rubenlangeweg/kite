import Foundation
import Testing
@testable import Kite

@Suite("BranchParser")
struct BranchParserTests {
    private static let branchFormat =
        "%(refname:short)%00%(refname)%00%(objectname)%00%(upstream:short)%00%(upstream:track)%00%(HEAD)"

    @Test("happy-path: local branch with feature/ prefix parses cleanly")
    func parsesLocalBranchWithSlash() throws {
        let repo = GitFixtureHelper.tempURL()
        defer { GitFixtureHelper.cleanup(repo) }
        try GitFixtureHelper.cleanRepo(at: repo)
        try GitFixtureHelper.exec(["branch", "feature/x"], cwd: repo)

        let raw = try GitFixtureHelper.capture(
            ["branch", "--list", "--format=\(Self.branchFormat)"], cwd: repo
        )
        let branches = try BranchParser.parse(raw)

        #expect(branches.count == 2)
        let feature = try #require(branches.first { $0.shortName == "feature/x" })
        #expect(feature.fullName == "refs/heads/feature/x")
        #expect(feature.sha.count == 40)
        #expect(feature.upstream == nil)
        #expect(feature.ahead == nil)
        #expect(feature.behind == nil)
        #expect(feature.isGone == false)
        #expect(feature.isRemote == false)
        #expect(feature.remote == nil)
        #expect(feature.isHead == false)

        let main = try #require(branches.first { $0.shortName == "main" })
        #expect(main.isHead == true, "main should be the current branch in cleanRepo")
    }

    @Test("empty input returns an empty array (not a throw)")
    func emptyInputReturnsEmpty() throws {
        #expect(try BranchParser.parse("") == [])
        #expect(try BranchParser.parse("\n") == [])
    }

    @Test("tracking branch with ahead/behind gets counts extracted")
    func aheadBehindParsed() throws {
        // Synthetic fixture — real ahead/behind requires a remote fetch flow
        // that's outside this parser's concern. The documented format string
        // is still produced by git for branches with a set upstream.
        let line = "main\u{00}refs/heads/main\u{00}1111111111111111111111111111111111111111" +
            "\u{00}origin/main\u{00}[ahead 2, behind 4]\u{00}*\n"
        let branches = try BranchParser.parse(line)
        #expect(branches.count == 1)
        let parsed = branches[0]
        #expect(parsed.upstream == "origin/main")
        #expect(parsed.ahead == 2)
        #expect(parsed.behind == 4)
        #expect(parsed.isGone == false)
        #expect(parsed.isHead == true)
    }

    @Test("[gone] upstream marker sets isGone and clears counts to 0")
    func goneUpstreamParsed() throws {
        let line = "stale\u{00}refs/heads/stale\u{00}2222222222222222222222222222222222222222" +
            "\u{00}origin/stale\u{00}[gone]\u{00} \n"
        let branches = try BranchParser.parse(line)
        #expect(branches.count == 1)
        let parsed = branches[0]
        #expect(parsed.isGone == true)
        #expect(parsed.upstream == "origin/stale")
        #expect(parsed.ahead == 0)
        #expect(parsed.behind == 0)
        #expect(parsed.isHead == false)
    }

    @Test("remote branches reported with isRemote + remote = 'origin'")
    func remoteBranchParsed() throws {
        // `git branch -r --format=...` emits records with `refs/remotes/...`
        // full refnames. Simulate a single remote row.
        let line = "origin/feature/x\u{00}refs/remotes/origin/feature/x" +
            "\u{00}3333333333333333333333333333333333333333\u{00}\u{00}\u{00} \n"
        let branches = try BranchParser.parse(line)
        let parsed = try #require(branches.first)
        #expect(parsed.isRemote == true)
        #expect(parsed.remote == "origin")
        #expect(parsed.shortName == "origin/feature/x")
        #expect(parsed.fullName == "refs/remotes/origin/feature/x")
        #expect(parsed.upstream == nil)
        #expect(parsed.ahead == nil)
        #expect(parsed.behind == nil)
    }

    @Test("detached-HEAD fixture: HEAD column is ' ' for every branch")
    func detachedHeadHasNoCurrentBranch() throws {
        let repo = GitFixtureHelper.tempURL()
        defer { GitFixtureHelper.cleanup(repo) }
        try GitFixtureHelper.cleanRepo(at: repo)
        // Create a second commit so we can detach to the first.
        try "hello".write(
            to: repo.appendingPathComponent("README"), atomically: true, encoding: .utf8
        )
        try GitFixtureHelper.exec(["add", "README"], cwd: repo)
        try GitFixtureHelper.exec([
            "-c",
            "user.email=t@k.l",
            "-c",
            "user.name=T",
            "commit",
            "-m",
            "second"
        ], cwd: repo)
        // Detach HEAD to the previous commit.
        try GitFixtureHelper.exec(["switch", "--detach", "HEAD^"], cwd: repo)

        let raw = try GitFixtureHelper.capture(
            ["branch", "--list", "--format=\(Self.branchFormat)"], cwd: repo
        )
        let branches = try BranchParser.parse(raw)
        // No branch is HEAD when detached.
        #expect(branches.contains { $0.isHead } == false)
    }

    @Test("malformed line (too few fields) throws ParseError")
    func malformedThrows() {
        let line = "main\u{00}refs/heads/main\u{00}abc\n"
        #expect(throws: ParseError.self) {
            _ = try BranchParser.parse(line)
        }
    }
}
