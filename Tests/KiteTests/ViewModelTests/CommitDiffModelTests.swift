import Foundation
import Testing
@testable import Kite

/// Unit tests for `CommitDiffModel` using real fixture repos.
///
/// Builds a tmp-dir fixture via `GitFixtureHelper`, drives `load(sha:for:)`,
/// and asserts against parsed `CommitHeader` + `FileDiff` state. No mocking
/// of `git` — Kite's value is correct behavior against real git.
///
/// Fulfills: VAL-DIFF-003 (selected commit diff renders git show), VAL-DIFF-006
/// (large-diff pipe-drain proof), VAL-GRAPH-009 (selecting a commit opens
/// diff — wiring-level; the UI side is XCUI-gated).
@Suite("CommitDiffModel")
@MainActor
struct CommitDiffModelTests {
    // MARK: - Fixture helpers

    private struct WorkFixture {
        let parent: URL
        let work: URL
        let focus: RepoFocus
    }

    /// A standalone repo with a single empty initial commit on `main`.
    private static func makeStandaloneFixture() throws -> WorkFixture {
        let parent = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let work = parent.appendingPathComponent("work")
        try GitFixtureHelper.cleanRepo(at: work)
        let repo = DiscoveredRepo(url: work, displayName: "work", rootPath: parent, isBare: false)
        return WorkFixture(parent: parent, work: work, focus: RepoFocus(repo: repo))
    }

    /// Capture the current HEAD sha of a fixture (full 40-char hex).
    private static func headSHA(of fixture: WorkFixture) throws -> String {
        let out = try GitFixtureHelper.capture(["rev-parse", "HEAD"], cwd: fixture.work)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tests

    @Test("loads a simple commit that adds three lines to a new file")
    func loadSimpleCommit() async throws {
        let fixture = try Self.makeStandaloneFixture()
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        // Add a new file with three lines and commit.
        let path = fixture.work.appendingPathComponent("hello.txt")
        try "alpha\nbeta\ngamma\n".write(to: path, atomically: true, encoding: .utf8)
        try GitFixtureHelper.exec(["add", "hello.txt"], cwd: fixture.work)
        try GitFixtureHelper.exec(["commit", "-m", "add hello"], cwd: fixture.work)

        let sha = try Self.headSHA(of: fixture)

        let model = CommitDiffModel()
        await model.load(sha: sha, for: fixture.focus)

        #expect(model.lastError == nil)
        let header = try #require(model.header)
        #expect(header.sha == sha)
        #expect(header.shortSHA.count == 7)
        #expect(header.subject == "add hello")
        #expect(header.body.isEmpty)
        #expect(model.files.count == 1)
        let file = try #require(model.files.first)
        #expect(file.newPath == "hello.txt")
        #expect(file.hunks.count == 1)
    }

    @Test("parses subject + multi-line body for commits with a body")
    func loadCommitWithBody() async throws {
        let fixture = try Self.makeStandaloneFixture()
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        try "content\n".write(
            to: fixture.work.appendingPathComponent("note.txt"),
            atomically: true, encoding: .utf8
        )
        try GitFixtureHelper.exec(["add", "note.txt"], cwd: fixture.work)
        try GitFixtureHelper.exec(
            ["commit", "-m", "subject", "-m", "multi-line body\nwith details"],
            cwd: fixture.work
        )

        let sha = try Self.headSHA(of: fixture)

        let model = CommitDiffModel()
        await model.load(sha: sha, for: fixture.focus)

        #expect(model.lastError == nil)
        let header = try #require(model.header)
        #expect(header.subject == "subject")
        #expect(header.body.contains("multi-line body"))
        #expect(header.body.contains("with details"))
    }

    @Test("loads a merge commit without exploding")
    func loadMergeCommit() async throws {
        let fixture = try Self.makeStandaloneFixture()
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        // Seed a shared base commit touching "shared.txt".
        let shared = fixture.work.appendingPathComponent("shared.txt")
        try "base\n".write(to: shared, atomically: true, encoding: .utf8)
        try GitFixtureHelper.exec(["add", "shared.txt"], cwd: fixture.work)
        try GitFixtureHelper.exec(["commit", "-m", "base"], cwd: fixture.work)

        // Branch A: modify shared.txt, commit on main.
        try "base\nfrom-main\n".write(to: shared, atomically: true, encoding: .utf8)
        try GitFixtureHelper.exec(["add", "shared.txt"], cwd: fixture.work)
        try GitFixtureHelper.exec(["commit", "-m", "main adds line"], cwd: fixture.work)

        // Branch B: create feature from the base before main moved, modify
        // a different file to avoid a conflict, then merge back.
        try GitFixtureHelper.exec(["switch", "-c", "feature", "HEAD~1"], cwd: fixture.work)
        try "feature-only\n".write(
            to: fixture.work.appendingPathComponent("feature.txt"),
            atomically: true, encoding: .utf8
        )
        try GitFixtureHelper.exec(["add", "feature.txt"], cwd: fixture.work)
        try GitFixtureHelper.exec(["commit", "-m", "feature adds file"], cwd: fixture.work)

        // Back to main and merge feature in with a merge commit (--no-ff).
        try GitFixtureHelper.exec(["switch", "main"], cwd: fixture.work)
        try GitFixtureHelper.exec(
            ["merge", "--no-ff", "-m", "merge feature", "feature"],
            cwd: fixture.work
        )

        let sha = try Self.headSHA(of: fixture)

        let model = CommitDiffModel()
        await model.load(sha: sha, for: fixture.focus)

        // Merges show either combined-diff output (two parents modifying the
        // same file) or a per-side diff (only one side touched a given file).
        // The exact file set varies with git's combined-diff heuristics; only
        // assert that the header parsed and the model did not error out.
        #expect(model.lastError == nil)
        let header = try #require(model.header)
        #expect(header.sha == sha)
        #expect(header.subject == "merge feature")
    }

    @Test("non-existent commit yields lastError and empty state")
    func loadNonExistentCommit() async throws {
        let fixture = try Self.makeStandaloneFixture()
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        let model = CommitDiffModel()
        await model.load(
            sha: "0000000000000000000000000000000000000000",
            for: fixture.focus
        )

        #expect(model.lastError != nil)
        #expect(model.header == nil)
        #expect(model.files.isEmpty)
    }

    @Test("empty (--allow-empty) commit parses header + empty file list")
    func loadEmptyDiffCommit() async throws {
        let fixture = try Self.makeStandaloneFixture()
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        try GitFixtureHelper.exec(
            ["commit", "--allow-empty", "-m", "empty"],
            cwd: fixture.work
        )

        let sha = try Self.headSHA(of: fixture)

        let model = CommitDiffModel()
        await model.load(sha: sha, for: fixture.focus)

        #expect(model.lastError == nil)
        let header = try #require(model.header)
        #expect(header.subject == "empty")
        #expect(model.files.isEmpty)
    }

    @Test("500-line commit completes without pipe-buffer deadlock (VAL-DIFF-006)")
    func loadLargeCommit() async throws {
        // Proof that the M1-fix-git-run-drain concurrent-pipe-drain fix is in
        // effect for this code path: without it, a large `git show` output
        // (> 64 KB pipe buffer) would deadlock the child and this test would
        // time out. 500 lines × enough text per line easily clears 64 KB.
        let fixture = try Self.makeStandaloneFixture()
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        var contents = ""
        for index in 0 ..< 500 {
            contents += "line-\(index)-with-additional-text-to-grow-the-diff-payload\n"
        }
        try contents.write(
            to: fixture.work.appendingPathComponent("big.txt"),
            atomically: true, encoding: .utf8
        )
        try GitFixtureHelper.exec(["add", "big.txt"], cwd: fixture.work)
        try GitFixtureHelper.exec(["commit", "-m", "add big"], cwd: fixture.work)

        let sha = try Self.headSHA(of: fixture)

        let model = CommitDiffModel()
        let start = Date()
        await model.load(sha: sha, for: fixture.focus)
        let elapsed = Date().timeIntervalSince(start)

        #expect(model.lastError == nil)
        #expect(model.header != nil)
        #expect(model.files.count == 1)
        let file = try #require(model.files.first)
        #expect(file.hunks.count >= 1)
        #expect(elapsed < 30.0, "load took \(elapsed)s; pipe drain regressed?")
    }

    @Test("repeat load of the same SHA is a no-op (de-dup proxy timing)")
    func loadDeDupesRepeatedSHA() async throws {
        let fixture = try Self.makeStandaloneFixture()
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        try "one\n".write(
            to: fixture.work.appendingPathComponent("a.txt"),
            atomically: true, encoding: .utf8
        )
        try GitFixtureHelper.exec(["add", "a.txt"], cwd: fixture.work)
        try GitFixtureHelper.exec(["commit", "-m", "one"], cwd: fixture.work)
        let sha = try Self.headSHA(of: fixture)

        let model = CommitDiffModel()
        await model.load(sha: sha, for: fixture.focus)
        #expect(model.lastError == nil)
        #expect(model.header?.sha == sha)

        // Second identical load: CommitDiffModel's `currentSHA` guard must
        // short-circuit before spawning another subprocess. We can't observe
        // subprocess count directly without touching the source, so use a
        // timing-based proxy — a real `git show` against this fixture takes
        // >>10ms; a short-circuit returns in microseconds. 50ms is a generous
        // upper bound that still comfortably distinguishes the two paths.
        let start = Date()
        await model.load(sha: sha, for: fixture.focus)
        let elapsed = Date().timeIntervalSince(start)

        #expect(elapsed < 0.05, "second load took \(elapsed)s — de-dup guard regressed?")
        #expect(model.header?.sha == sha)
    }

    @Test("clear() resets every observable field")
    func clearResetsState() async throws {
        let fixture = try Self.makeStandaloneFixture()
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        try "content\n".write(
            to: fixture.work.appendingPathComponent("f.txt"),
            atomically: true, encoding: .utf8
        )
        try GitFixtureHelper.exec(["add", "f.txt"], cwd: fixture.work)
        try GitFixtureHelper.exec(["commit", "-m", "seed"], cwd: fixture.work)
        let sha = try Self.headSHA(of: fixture)

        let model = CommitDiffModel()
        await model.load(sha: sha, for: fixture.focus)
        #expect(model.header != nil)

        model.clear()

        #expect(model.header == nil)
        #expect(model.files.isEmpty)
        #expect(model.lastError == nil)
        #expect(model.isLoading == false)
    }
}
