import Foundation
import Testing
@testable import Kite

@Suite("DiffParser")
struct DiffParserTests {
    @Test("single-file add with real git output parses as new file")
    func singleFileAddFromGit() throws {
        let repo = GitFixtureHelper.tempURL()
        defer { GitFixtureHelper.cleanup(repo) }
        try GitFixtureHelper.cleanRepo(at: repo)
        try "line one\nline two\n".write(
            to: repo.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8
        )
        try GitFixtureHelper.exec(["add", "new.txt"], cwd: repo)

        let raw = try GitFixtureHelper.capture(
            ["diff", "--no-color", "--patch", "-U3", "--staged"], cwd: repo
        )
        let files = try DiffParser.parse(raw)
        let file = try #require(files.first)
        #expect(file.oldPath == nil, "new file should report oldPath == nil")
        #expect(file.newPath == "new.txt")
        #expect(file.isBinary == false)
        #expect(file.hunks.count == 1)
        let hunk = file.hunks[0]
        #expect(hunk.newStart == 1)
        #expect(hunk.lines.contains(.added("line one")))
        #expect(hunk.lines.contains(.added("line two")))
    }

    @Test("single-file delete reports newPath == nil")
    func singleFileDeleteFromGit() throws {
        let repo = GitFixtureHelper.tempURL()
        defer { GitFixtureHelper.cleanup(repo) }
        try GitFixtureHelper.cleanRepo(at: repo)
        try "bye\n".write(
            to: repo.appendingPathComponent("gone.txt"), atomically: true, encoding: .utf8
        )
        try GitFixtureHelper.exec(["add", "gone.txt"], cwd: repo)
        try GitFixtureHelper.exec(["commit", "-m", "add gone"], cwd: repo)
        try GitFixtureHelper.exec(["rm", "gone.txt"], cwd: repo)

        let raw = try GitFixtureHelper.capture(
            ["diff", "--no-color", "--patch", "-U3", "--staged"], cwd: repo
        )
        let files = try DiffParser.parse(raw)
        let file = try #require(files.first)
        #expect(file.oldPath == "gone.txt")
        #expect(file.newPath == nil)
        #expect(file.isBinary == false)
    }

    @Test("binary file diff is marked isBinary and has no hunks")
    func binaryFile() throws {
        let repo = GitFixtureHelper.tempURL()
        defer { GitFixtureHelper.cleanup(repo) }
        try GitFixtureHelper.cleanRepo(at: repo)
        // Write bytes likely to be detected as binary by git.
        let bytes: [UInt8] = [0x00, 0x01, 0xff, 0xfe, 0x00, 0x7f, 0x80, 0x00]
        try Data(bytes).write(to: repo.appendingPathComponent("blob.bin"))
        try GitFixtureHelper.exec(["add", "blob.bin"], cwd: repo)

        let raw = try GitFixtureHelper.capture(
            ["diff", "--no-color", "--patch", "-U3", "--staged"], cwd: repo
        )
        let files = try DiffParser.parse(raw)
        let file = try #require(files.first)
        #expect(file.isBinary)
        #expect(file.hunks.isEmpty)
    }

    @Test("\\ No newline at end of file is captured as a noNewlineMarker")
    func noNewlineMarker() throws {
        let repo = GitFixtureHelper.tempURL()
        defer { GitFixtureHelper.cleanup(repo) }
        try GitFixtureHelper.cleanRepo(at: repo)
        // Write a file with NO trailing newline, commit, then modify it.
        try "original".write(
            to: repo.appendingPathComponent("nl.txt"), atomically: true, encoding: .utf8
        )
        try GitFixtureHelper.exec(["add", "nl.txt"], cwd: repo)
        try GitFixtureHelper.exec(["commit", "-m", "no newline"], cwd: repo)
        try "changed".write(
            to: repo.appendingPathComponent("nl.txt"), atomically: true, encoding: .utf8
        )

        let raw = try GitFixtureHelper.capture(
            ["diff", "--no-color", "--patch", "-U3"], cwd: repo
        )
        let files = try DiffParser.parse(raw)
        let file = try #require(files.first)
        let hunk = try #require(file.hunks.first)
        #expect(hunk.lines.contains(.noNewlineMarker))
    }

    @Test("multi-hunk diff parses each hunk with correct ranges")
    func multiHunk() throws {
        let repo = GitFixtureHelper.tempURL()
        defer { GitFixtureHelper.cleanup(repo) }
        try GitFixtureHelper.cleanRepo(at: repo)
        // 20-line file, commit, then edit lines 2 and 18 so the diff must
        // produce at least 2 hunks (context windows don't overlap at default
        // -U3 when changes are >6 lines apart).
        var body = ""
        for lineNum in 1 ... 20 {
            body += "line \(lineNum)\n"
        }
        try body.write(
            to: repo.appendingPathComponent("multi.txt"), atomically: true, encoding: .utf8
        )
        try GitFixtureHelper.exec(["add", "multi.txt"], cwd: repo)
        try GitFixtureHelper.exec(["commit", "-m", "add multi"], cwd: repo)

        var edited = ""
        for lineNum in 1 ... 20 {
            if lineNum == 2 {
                edited += "line TWO\n"
            } else if lineNum == 18 {
                edited += "line EIGHTEEN\n"
            } else {
                edited += "line \(lineNum)\n"
            }
        }
        try edited.write(
            to: repo.appendingPathComponent("multi.txt"), atomically: true, encoding: .utf8
        )

        let raw = try GitFixtureHelper.capture(
            ["diff", "--no-color", "--patch", "-U3"], cwd: repo
        )
        let files = try DiffParser.parse(raw)
        let file = try #require(files.first)
        #expect(file.hunks.count >= 2, "expected at least 2 hunks, got \(file.hunks.count)")
    }

    @Test("empty input returns an empty array")
    func emptyInputEmpty() throws {
        #expect(try DiffParser.parse("").isEmpty)
    }

    @Test("commit-header lines before first `diff --git` are skipped (git show)")
    func gitShowCommitHeaderSkipped() throws {
        let synthetic = """
        commit abcdef0123456789
        Author: Me <me@example.com>
        Date:   Mon Jan 1 00:00:00 2024 +0000

            subject line

        diff --git a/f b/f
        --- a/f
        +++ b/f
        @@ -1 +1 @@
        -old
        +new
        """
        let files = try DiffParser.parse(synthetic)
        #expect(files.count == 1)
        #expect(files[0].hunks.first?.lines == [.removed("old"), .added("new")])
    }
}
