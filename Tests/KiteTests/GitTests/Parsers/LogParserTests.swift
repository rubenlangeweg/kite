import Foundation
import Testing
@testable import Kite

@Suite("LogParser")
struct LogParserTests {
    private static let logFormat = "%H%x00%P%x00%an%x00%ae%x00%at%x00%s"

    @Test("happy-path: parses a 2-commit linear history from real git")
    func parsesLinearHistory() throws {
        let repo = GitFixtureHelper.tempURL()
        defer { GitFixtureHelper.cleanup(repo) }
        try GitFixtureHelper.cleanRepo(at: repo)
        try "first".write(
            to: repo.appendingPathComponent("A.txt"), atomically: true, encoding: .utf8
        )
        try GitFixtureHelper.exec(["add", "A.txt"], cwd: repo)
        try GitFixtureHelper.exec(["commit", "-m", "add A"], cwd: repo)

        let raw = try GitFixtureHelper.capture(
            ["log", "--all", "--topo-order", "--format=\(Self.logFormat)", "-n", "200", "-z"],
            cwd: repo
        )
        let commits = try LogParser.parse(raw)

        #expect(commits.count == 2)
        #expect(commits[0].subject == "add A")
        #expect(commits[0].parents.count == 1)
        #expect(commits[0].authorName == "Kite Tests")
        #expect(commits[0].authorEmail == "tests@kite.local")
        #expect(commits[1].subject == "initial")
        #expect(commits[1].parents.isEmpty, "root commit has no parents")
    }

    @Test("empty repo produces an empty array (no throw)")
    func emptyRepo() throws {
        let repo = GitFixtureHelper.tempURL()
        defer { GitFixtureHelper.cleanup(repo) }
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try GitFixtureHelper.exec(["init", "-b", "main"], cwd: repo)

        // A completely empty repo — git log exits non-zero, but if a caller
        // guards and passes "" we still must not throw.
        #expect(try LogParser.parse("") == [])
    }

    @Test("merge commit preserves 2 parents in order")
    func mergeHasTwoParents() throws {
        let repo = GitFixtureHelper.tempURL()
        defer { GitFixtureHelper.cleanup(repo) }
        try GitFixtureHelper.cleanRepo(at: repo)
        try GitFixtureHelper.exec(["branch", "feature"], cwd: repo)
        // Advance main.
        try "m1".write(
            to: repo.appendingPathComponent("m.txt"), atomically: true, encoding: .utf8
        )
        try GitFixtureHelper.exec(["add", "m.txt"], cwd: repo)
        try GitFixtureHelper.exec(["commit", "-m", "main advance"], cwd: repo)
        // Advance feature.
        try GitFixtureHelper.exec(["switch", "feature"], cwd: repo)
        try "f1".write(
            to: repo.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8
        )
        try GitFixtureHelper.exec(["add", "f.txt"], cwd: repo)
        try GitFixtureHelper.exec(["commit", "-m", "feature advance"], cwd: repo)
        // Merge feature into main (no-ff to force a merge commit).
        try GitFixtureHelper.exec(["switch", "main"], cwd: repo)
        try GitFixtureHelper.exec(["merge", "--no-ff", "feature", "-m", "merge feature"], cwd: repo)

        let raw = try GitFixtureHelper.capture(
            ["log", "--all", "--topo-order", "--format=\(Self.logFormat)", "-n", "200", "-z"],
            cwd: repo
        )
        let commits = try LogParser.parse(raw)
        let merge = try #require(commits.first { $0.subject == "merge feature" })
        #expect(merge.parents.count == 2)
    }

    @Test("octopus merge with 3 parents is represented correctly")
    func octopusMerge() throws {
        let repo = GitFixtureHelper.tempURL()
        defer { GitFixtureHelper.cleanup(repo) }
        try GitFixtureHelper.cleanRepo(at: repo)

        // Create two side branches off main, each with one commit. Merging
        // both into main yields an octopus merge with 3 parents (main's tip
        // plus each branch's tip).
        for name in ["a", "b"] {
            try GitFixtureHelper.exec(["switch", "-c", name, "main"], cwd: repo)
            try name.write(
                to: repo.appendingPathComponent("\(name).txt"),
                atomically: true, encoding: .utf8
            )
            try GitFixtureHelper.exec(["add", "\(name).txt"], cwd: repo)
            try GitFixtureHelper.exec(["commit", "-m", "\(name) branch"], cwd: repo)
        }
        try GitFixtureHelper.exec(["switch", "main"], cwd: repo)
        try GitFixtureHelper.exec(
            ["merge", "--no-ff", "a", "b", "-m", "octopus merge"], cwd: repo
        )

        let raw = try GitFixtureHelper.capture(
            ["log", "--all", "--topo-order", "--format=\(Self.logFormat)", "-n", "200", "-z"],
            cwd: repo
        )
        let commits = try LogParser.parse(raw)
        let octopus = try #require(commits.first { $0.subject == "octopus merge" })
        #expect(octopus.parents.count == 3, "expected 3 parents, got \(octopus.parents)")
    }

    @Test("unicode subject survives round-trip")
    func unicodeSubject() throws {
        let repo = GitFixtureHelper.tempURL()
        defer { GitFixtureHelper.cleanup(repo) }
        try GitFixtureHelper.cleanRepo(at: repo)
        let subject = "café ✨ commit — 日本語"
        try "x".write(
            to: repo.appendingPathComponent("x.txt"), atomically: true, encoding: .utf8
        )
        try GitFixtureHelper.exec(["add", "x.txt"], cwd: repo)
        try GitFixtureHelper.exec(["commit", "-m", subject], cwd: repo)

        let raw = try GitFixtureHelper.capture(
            ["log", "--all", "--topo-order", "--format=\(Self.logFormat)", "-n", "200", "-z"],
            cwd: repo
        )
        let commits = try LogParser.parse(raw)
        #expect(commits.contains { $0.subject == subject })
    }

    @Test("malformed timestamp throws ParseError")
    func malformedTimestampThrows() {
        // Synthetic record with a non-numeric %at — must throw, not silently
        // coerce to 0 (parser must surface bad input).
        let record = "abc123\u{00}\u{00}Me\u{00}me@x\u{00}NOT_A_NUMBER\u{00}broken\u{00}"
        #expect(throws: ParseError.self) {
            _ = try LogParser.parse(record)
        }
    }

    @Test("misaligned field count throws ParseError")
    func misalignedFieldCountThrows() {
        // Five fields instead of six — simulates a subject that contained a
        // raw \0 byte (should be impossible with git, but we must guard).
        let record = "abc123\u{00}\u{00}Me\u{00}me@x\u{00}1700000000"
        #expect(throws: ParseError.self) {
            _ = try LogParser.parse(record)
        }
    }
}
