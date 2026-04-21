import Foundation
import Testing
@testable import Kite

/// Unit tests for `UncommittedDiffModel` using real fixture repos.
///
/// Every test builds a tmp-dir fixture via `GitFixtureHelper`, drives
/// `reload(for:)`, and asserts against the parsed `FileDiff` arrays. No
/// mocking of `git` — Kite's value is correct behavior against real git.
///
/// Fulfills: VAL-DIFF-001 (two-arm fetch + parse), VAL-DIFF-002 (clean-tree
/// emptiness contract), VAL-DIFF-006 (large-diff drain proof).
@Suite("UncommittedDiffModel")
@MainActor
struct UncommittedDiffModelTests {
    // MARK: - Fixture helpers

    private struct WorkFixture {
        let parent: URL
        let work: URL
        let focus: RepoFocus
    }

    /// A standalone repo with a single initial commit on `main`. No remote.
    private static func makeStandaloneFixture() throws -> WorkFixture {
        let parent = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let work = parent.appendingPathComponent("work")
        try GitFixtureHelper.cleanRepo(at: work)
        let repo = DiscoveredRepo(url: work, displayName: "work", rootPath: parent, isBare: false)
        return WorkFixture(parent: parent, work: work, focus: RepoFocus(repo: repo))
    }

    /// A standalone repo pre-seeded with a tracked `tracked.txt` so tests
    /// have something to modify (and thereby exercise the "modify tracked"
    /// code path that `git diff` actually reports — untracked-only repos
    /// produce empty `git diff` output).
    private static func makeSeededFixture(initialContent: String = "v1") throws -> WorkFixture {
        let fixture = try makeStandaloneFixture()
        try initialContent.write(
            to: fixture.work.appendingPathComponent("tracked.txt"),
            atomically: true, encoding: .utf8
        )
        try GitFixtureHelper.exec(["add", "tracked.txt"], cwd: fixture.work)
        try GitFixtureHelper.exec(["commit", "-m", "add tracked"], cwd: fixture.work)
        return fixture
    }

    // MARK: - Tests

    @Test("clean working tree produces empty staged + unstaged, no error")
    func cleanTreeEmpty() async throws {
        let fixture = try Self.makeStandaloneFixture()
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        let model = UncommittedDiffModel()
        await model.reload(for: fixture.focus)

        #expect(model.unstaged.isEmpty)
        #expect(model.staged.isEmpty)
        #expect(model.lastError == nil)
    }

    @Test("modified-not-staged tracked file populates unstaged with one FileDiff")
    func unstagedChangesPopulated() async throws {
        let fixture = try Self.makeSeededFixture(initialContent: "v1")
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        // Modify the tracked file in the worktree WITHOUT staging. This is
        // the exact "unstaged change" `git diff` (no --staged) reports on.
        try "v2-worktree".write(
            to: fixture.work.appendingPathComponent("tracked.txt"),
            atomically: true, encoding: .utf8
        )

        let model = UncommittedDiffModel()
        await model.reload(for: fixture.focus)

        #expect(model.lastError == nil)
        #expect(model.staged.isEmpty)
        #expect(model.unstaged.count == 1, "expected 1 unstaged file; got \(model.unstaged.count)")
        let diff = try #require(model.unstaged.first)
        #expect(diff.newPath == "tracked.txt")
        #expect(diff.isBinary == false)
        #expect(!diff.hunks.isEmpty)
    }

    @Test("staged modification populates staged with one FileDiff")
    func stagedChangesPopulated() async throws {
        let fixture = try Self.makeSeededFixture(initialContent: "v1")
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        try "v2-staged".write(
            to: fixture.work.appendingPathComponent("tracked.txt"),
            atomically: true, encoding: .utf8
        )
        try GitFixtureHelper.exec(["add", "tracked.txt"], cwd: fixture.work)

        let model = UncommittedDiffModel()
        await model.reload(for: fixture.focus)

        #expect(model.lastError == nil)
        #expect(model.unstaged.isEmpty)
        #expect(model.staged.count == 1, "expected 1 staged file; got \(model.staged.count)")
        let diff = try #require(model.staged.first)
        #expect(diff.newPath == "tracked.txt")
    }

    @Test("mixed staged (file A) + unstaged (file B) populates both arms")
    func mixedStagedAndUnstaged() async throws {
        let fixture = try Self.makeStandaloneFixture()
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        // Pre-commit two tracked files: A and B.
        try "a-v1".write(to: fixture.work.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b-v1".write(to: fixture.work.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try GitFixtureHelper.exec(["add", "a.txt", "b.txt"], cwd: fixture.work)
        try GitFixtureHelper.exec(["commit", "-m", "seed a + b"], cwd: fixture.work)

        // Stage a modification to A.
        try "a-v2".write(to: fixture.work.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try GitFixtureHelper.exec(["add", "a.txt"], cwd: fixture.work)

        // Modify B but don't stage.
        try "b-v2".write(to: fixture.work.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let model = UncommittedDiffModel()
        await model.reload(for: fixture.focus)

        #expect(model.lastError == nil)
        #expect(model.staged.count == 1)
        #expect(model.unstaged.count == 1)
        #expect(model.staged.first?.newPath == "a.txt")
        #expect(model.unstaged.first?.newPath == "b.txt")
    }

    @Test("untracked files are NOT in git diff output (both arms empty)")
    func untrackedFilesNotInDiff() async throws {
        // Documented caveat: `git diff` (with or without --staged) does NOT
        // report untracked files. They only surface in `git status`. The
        // working-copy diff pane is therefore intentionally "blind" to a
        // repo whose only uncommitted change is a new, unstaged file —
        // `StatusHeaderModel` (VAL-BRANCH-005) is what surfaces that state.
        let fixture = try Self.makeStandaloneFixture()
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        try "fresh".write(
            to: fixture.work.appendingPathComponent("untracked.txt"),
            atomically: true, encoding: .utf8
        )

        let model = UncommittedDiffModel()
        await model.reload(for: fixture.focus)

        #expect(model.lastError == nil)
        #expect(model.unstaged.isEmpty, "git diff must not report untracked files")
        #expect(model.staged.isEmpty)
    }

    @Test("large 1000-line modification completes under 30s (M1 drain in effect)")
    func largeDiffSucceeds() async throws {
        // Proof that the M1-fix-git-run-drain concurrent-pipe-drain fix is
        // in effect for this code path: without it, a large `git diff`
        // output (> 64 KB pipe buffer) would deadlock the child and this
        // test would time out.
        let fixture = try Self.makeStandaloneFixture()
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        let bigFile = fixture.work.appendingPathComponent("big.txt")
        // Seed with 1000 lines, commit.
        var original = ""
        for index in 0 ..< 1000 {
            original += "original-line-\(index)\n"
        }
        try original.write(to: bigFile, atomically: true, encoding: .utf8)
        try GitFixtureHelper.exec(["add", "big.txt"], cwd: fixture.work)
        try GitFixtureHelper.exec(["commit", "-m", "add big"], cwd: fixture.work)

        // Rewrite every line so the diff is ~1000 removed + ~1000 added lines
        // — well past the ~64 KB pipe buffer that used to deadlock Git.run.
        var rewritten = ""
        for index in 0 ..< 1000 {
            rewritten += "modified-line-\(index)-with-additional-text-to-grow-the-diff-payload\n"
        }
        try rewritten.write(to: bigFile, atomically: true, encoding: .utf8)

        let model = UncommittedDiffModel()

        let start = Date()
        await model.reload(for: fixture.focus)
        let elapsed = Date().timeIntervalSince(start)

        #expect(model.lastError == nil)
        #expect(model.unstaged.count == 1)
        #expect(elapsed < 30.0, "reload took \(elapsed)s; pipe drain regressed?")
        let diff = try #require(model.unstaged.first)
        #expect(!diff.hunks.isEmpty)
        // Sanity-check we captured enough lines to actually exceed the pipe
        // buffer threshold.
        let totalLines = diff.hunks.reduce(0) { $0 + $1.lines.count }
        #expect(totalLines >= 1000, "expected at least 1000 diff lines, got \(totalLines)")
    }

    @Test("reload cancels prior in-flight reload without crash or state tear")
    func reloadCancelsPriorTask() async throws {
        let fixture = try Self.makeSeededFixture(initialContent: "v1")
        defer {
            fixture.focus.shutdown()
            GitFixtureHelper.cleanup(fixture.parent)
        }

        try "v2-worktree".write(
            to: fixture.work.appendingPathComponent("tracked.txt"),
            atomically: true, encoding: .utf8
        )

        let model = UncommittedDiffModel()

        // Kick off reload #1 but don't await it; immediately start reload #2
        // which should cancel reload #1. We await #2's completion so the
        // assertion runs against the winning state.
        async let first: Void = model.reload(for: fixture.focus)
        async let second: Void = model.reload(for: fixture.focus)

        _ = await (first, second)

        // Final state must be consistent — one unstaged FileDiff, no error.
        // The exact path exercised (cancel vs. natural race) isn't asserted
        // here; only that the successor reload converges.
        #expect(model.lastError == nil)
        #expect(model.unstaged.count == 1)
        #expect(model.staged.isEmpty)
    }
}
