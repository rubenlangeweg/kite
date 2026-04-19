import Foundation
import Testing
@testable import Kite

@Suite("ForEachRefParser")
struct ForEachRefParserTests {
    private static let format = "%(objectname) %(refname)%00%(*objectname)"

    @Test("happy-path: local branches and a lightweight tag map to expected RefKinds")
    func localBranchesAndLightweightTag() throws {
        let repo = GitFixtureHelper.tempURL()
        defer { GitFixtureHelper.cleanup(repo) }
        try GitFixtureHelper.cleanRepo(at: repo)
        try GitFixtureHelper.exec(["branch", "feature/x"], cwd: repo)
        try GitFixtureHelper.exec(["tag", "v0.1.0"], cwd: repo)

        let raw = try GitFixtureHelper.capture(
            ["for-each-ref", "--format=\(Self.format)"], cwd: repo
        )
        let map = try ForEachRefParser.parse(raw)

        // main and feature/x point at the same SHA (initial empty commit +
        // branch off HEAD), and the tag points at that commit too.
        let headSha = try GitFixtureHelper.capture(
            ["rev-parse", "HEAD"], cwd: repo
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let refs = try #require(map[headSha])
        // We expect: localBranch("main"), localBranch("feature/x"), tag("v0.1.0").
        #expect(refs.contains(.localBranch("main")))
        #expect(refs.contains(.localBranch("feature/x")))
        #expect(refs.contains(.tag("v0.1.0")))
    }

    @Test("annotated tag is joined on its peeled commit SHA, not the tag-object SHA")
    func annotatedTagPeels() throws {
        let repo = GitFixtureHelper.tempURL()
        defer { GitFixtureHelper.cleanup(repo) }
        try GitFixtureHelper.cleanRepo(at: repo)
        // Annotated tag — has its own tag object.
        try GitFixtureHelper.exec(
            [
                "-c",
                "user.email=t@k.l",
                "-c",
                "user.name=T",
                "tag",
                "-a",
                "v1.0.0",
                "-m",
                "release v1"
            ],
            cwd: repo
        )

        let raw = try GitFixtureHelper.capture(
            ["for-each-ref", "--format=\(Self.format)"], cwd: repo
        )
        let map = try ForEachRefParser.parse(raw)

        let commitSha = try GitFixtureHelper.capture(
            ["rev-parse", "HEAD"], cwd: repo
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let tagObjectSha = try GitFixtureHelper.capture(
            ["rev-parse", "v1.0.0"], cwd: repo
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        // Only tag when annotated does the tag-object SHA differ from the
        // peeled commit SHA. If for some reason they happened to collide (they
        // shouldn't), the test is still valid — we just can't assert the
        // tagObjectSha absence.
        let refsAtCommit = map[commitSha] ?? []
        #expect(refsAtCommit.contains(.tag("v1.0.0")))
        if tagObjectSha != commitSha {
            #expect(map[tagObjectSha] == nil, "annotated tag must not be keyed on tag-object SHA")
        }
    }

    @Test("symbolic HEAD pseudo-refs (HEAD, origin/HEAD) are excluded")
    func symbolicHeadExcluded() throws {
        let shared = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let input = [
            "\(shared) refs/heads/main\u{0000}",
            "\(shared) refs/remotes/origin/main\u{0000}",
            "\(shared) refs/remotes/origin/HEAD\u{0000}",
            "\(shared) HEAD\u{0000}"
        ].joined(separator: "\n") + "\n"

        let map = try ForEachRefParser.parse(input)
        let refs = try #require(map[shared])
        #expect(refs.contains(.localBranch("main")))
        #expect(refs.contains(.remoteBranch(remote: "origin", branch: "main")))
        #expect(refs.contains(.tag("v1.0.0")) == false)
        // The two symbolic entries should not have produced any RefKind.
        #expect(refs.count == 2)
    }

    @Test("empty input returns an empty dictionary")
    func emptyInputEmptyMap() throws {
        #expect(try ForEachRefParser.parse("").isEmpty)
    }

    @Test("remote branch with nested slash parses remote='origin' and branch='feat/x'")
    func remoteWithNestedSlash() throws {
        let sha = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        let input = "\(sha) refs/remotes/origin/feat/x\u{0000}\n"
        let map = try ForEachRefParser.parse(input)
        let refs = try #require(map[sha])
        #expect(refs.contains(.remoteBranch(remote: "origin", branch: "feat/x")))
    }

    @Test("malformed line (no space separator) throws")
    func malformedThrows() {
        let input = "missing-space-refname\u{0000}\n"
        #expect(throws: ParseError.self) {
            _ = try ForEachRefParser.parse(input)
        }
    }
}
