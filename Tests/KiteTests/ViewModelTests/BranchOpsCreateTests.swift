import Foundation
import Testing
@testable import Kite

/// Unit tests for `BranchOps.createBranch(_:on:)` using real fixture repos.
///
/// Fulfills:
///   - VAL-BRANCHOP-001 (creates a branch via `git switch -c`)
///   - VAL-BRANCHOP-003 (duplicate branch surfaces classified error)
///   - VAL-BRANCHOP-006 (dirty-tree error uses the documented copy)
///   - VAL-SEC-007 (shell-metacharacter-looking names are rejected before
///     `Process` ever runs)
@Suite("BranchOps.createBranch")
@MainActor
struct BranchOpsCreateTests {
    private struct Fixture {
        let parent: URL
        let repoURL: URL
        let repo: DiscoveredRepo
    }

    private static func makeFixture() throws -> Fixture {
        let parent = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let repoURL = parent.appendingPathComponent("repo")
        try GitFixtureHelper.cleanRepo(at: repoURL)
        // Add a second commit so `main` has real history — `git switch -c`
        // fails on a truly empty repo with no commits on the current branch.
        try GitFixtureHelper.exec(["commit", "--allow-empty", "-m", "second"], cwd: repoURL)
        let repo = DiscoveredRepo(
            url: repoURL,
            displayName: "repo",
            rootPath: parent,
            isBare: false
        )
        return Fixture(parent: parent, repoURL: repoURL, repo: repo)
    }

    private static func makeFocus(for fixture: Fixture) -> RepoFocus {
        RepoFocus(repo: fixture.repo)
    }

    /// Read the current branch via git. Returns `nil` when detached.
    private static func currentBranch(at url: URL) throws -> String? {
        let out = try GitFixtureHelper.capture(
            ["symbolic-ref", "--short", "HEAD"],
            cwd: url
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }

    /// True if the given local branch exists.
    private static func branchExists(_ name: String, at url: URL) throws -> Bool {
        let out = try GitFixtureHelper.capture(
            ["branch", "--list", name],
            cwd: url
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return !out.isEmpty
    }

    // MARK: - Tests

    /// VAL-BRANCHOP-001: create succeeds, branch exists, HEAD moved.
    @Test("creates a branch and moves HEAD", .timeLimit(.minutes(1)))
    func createBranchSuccess() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        let focus = Self.makeFocus(for: fixture)
        defer { focus.shutdown() }

        let toasts = ToastCenter()
        let ops = BranchOps(toasts: toasts)

        let ok = await ops.createBranch("feature/new", on: focus)
        #expect(ok, "createBranch should return true on success")

        #expect(try Self.branchExists("feature/new", at: fixture.repoURL))
        #expect(try Self.currentBranch(at: fixture.repoURL) == "feature/new")

        // Exactly one success toast.
        let successes = toasts.toasts.filter { $0.kind == .success }
        #expect(successes.count == 1)
        #expect(successes.first?.message.contains("feature/new") == true)
    }

    /// VAL-BRANCHOP-002 integration: an invalid name is rejected before the
    /// subprocess runs; no branch is created, a red error toast is posted.
    @Test("rejects an invalid name without running git", .timeLimit(.minutes(1)))
    func createBranchInvalidName() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        let focus = Self.makeFocus(for: fixture)
        defer { focus.shutdown() }

        let toasts = ToastCenter()
        let ops = BranchOps(toasts: toasts)

        let ok = await ops.createBranch("..", on: focus)
        #expect(!ok, "invalid names must not succeed")

        // No "..", no stray branch from a bypassed validator.
        #expect(try !(Self.branchExists("..", at: fixture.repoURL)))

        let errors = toasts.toasts.filter { $0.kind == .error }
        #expect(errors.count == 1)
        let msg = errors.first?.message ?? ""
        #expect(msg.contains("Invalid branch name"), "got: \(msg)")
    }

    /// VAL-BRANCHOP-003: attempting to re-create an existing branch surfaces
    /// a classified error toast. Repo stays on `main` (no silent switch).
    @Test("surfaces a sticky error for a duplicate branch", .timeLimit(.minutes(1)))
    func createDuplicateBranch() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        // Pre-create the branch via the fixture helper (bypasses BranchOps).
        try GitFixtureHelper.exec(["branch", "dup"], cwd: fixture.repoURL)

        let focus = Self.makeFocus(for: fixture)
        defer { focus.shutdown() }

        let toasts = ToastCenter()
        let ops = BranchOps(toasts: toasts)

        let ok = await ops.createBranch("dup", on: focus)
        #expect(!ok, "duplicate branch creation must fail")

        // HEAD should still be on main.
        #expect(try Self.currentBranch(at: fixture.repoURL) == "main")

        let errors = toasts.toasts.filter { $0.kind == .error }
        #expect(errors.count == 1)
        let detail = (errors.first?.detail ?? "").lowercased()
        // git's wording is: "fatal: a branch named 'dup' already exists"
        #expect(
            detail.contains("already exists") || detail.contains("exists"),
            "expected 'already exists' in stderr detail; got: \(detail)"
        )
    }

    /// VAL-BRANCHOP-006: `git switch` refuses to overwrite uncommitted
    /// changes in a tracked file. We set up the classic shape:
    ///   1. Create `file.txt` on main and commit it.
    ///   2. Branch off into `other`, change `file.txt`, commit.
    ///   3. Switch back to main, locally modify `file.txt` (unstaged).
    ///   4. Try to `switch other` — git refuses because the uncommitted
    ///      change would be clobbered, emitting
    ///      "Your local changes to the following files would be
    ///      overwritten…" which the classifier routes to
    ///      `GitError.dirtyWorkingTree`.
    ///
    /// `switchToLocal` and `createBranch` share the `runSwitch` helper, so
    /// verifying the documented copy on this path proves the same message
    /// would surface on a `createBranch` dirty-tree failure.
    @Test("dirty tree blocks switch with documented toast copy", .timeLimit(.minutes(1)))
    func dirtyTreeBlocksSwitch() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        // 1. Commit file.txt on main so it's a tracked file.
        let filePath = fixture.repoURL.appendingPathComponent("file.txt")
        try Data("v=main\n".utf8).write(to: filePath)
        try GitFixtureHelper.exec(["add", "file.txt"], cwd: fixture.repoURL)
        try GitFixtureHelper.exec(["commit", "-m", "main adds file"], cwd: fixture.repoURL)

        // 2. Branch off, change file.txt, commit on `other`.
        try GitFixtureHelper.exec(["checkout", "-b", "other"], cwd: fixture.repoURL)
        try Data("v=other\n".utf8).write(to: filePath)
        try GitFixtureHelper.exec(["add", "file.txt"], cwd: fixture.repoURL)
        try GitFixtureHelper.exec(["commit", "-m", "on other"], cwd: fixture.repoURL)

        // 3. Return to main; make an uncommitted change to the tracked file.
        try GitFixtureHelper.exec(["checkout", "main"], cwd: fixture.repoURL)
        try Data("v=main-dirty\n".utf8).write(to: filePath)

        let focus = Self.makeFocus(for: fixture)
        defer { focus.shutdown() }

        let toasts = ToastCenter()
        let ops = BranchOps(toasts: toasts)

        // 4. switching to `other` must fail with the dirty-tree classifier.
        let ok = await ops.switchToLocal("other", on: focus)
        #expect(!ok, "dirty tree should block switch")

        let errors = toasts.toasts.filter { $0.kind == .error }
        #expect(errors.count == 1)
        #expect(
            errors.first?.message == BranchOps.dirtyTreeMessage,
            "expected documented dirty-tree copy; got: \(errors.first?.message ?? "<nil>")"
        )
    }

    /// VAL-SEC-007: a branch name shaped like a shell-injection attempt is
    /// rejected by the validator BEFORE the subprocess runs. No branch is
    /// created; no side-effect file is written. Evidence: the validator
    /// returns non-nil and `/tmp/pwn-<uuid>` does not exist after the call.
    @Test("shell-injection-looking input is rejected before Process", .timeLimit(.minutes(1)))
    func processArgsNoShellInjection() async throws {
        let fixture = try Self.makeFixture()
        defer { GitFixtureHelper.cleanup(fixture.parent) }

        let focus = Self.makeFocus(for: fixture)
        defer { focus.shutdown() }

        let toasts = ToastCenter()
        let ops = BranchOps(toasts: toasts)

        // Unique sentinel so a prior test run can't taint this assertion.
        let sentinel = FileManager.default.temporaryDirectory
            .appendingPathComponent("kite-branchops-pwn-\(UUID().uuidString)")
        let payload = "x; touch \(sentinel.path)"

        // The validator flags ";" / space — we assert both "returned non-nil"
        // and "the sentinel was never created" for belt + braces.
        #expect(BranchNameValidator.validate(payload) != nil)

        let ok = await ops.createBranch(payload, on: focus)
        #expect(!ok)

        #expect(
            !FileManager.default.fileExists(atPath: sentinel.path),
            "shell-injection sentinel was created — Process argv safety compromised!"
        )

        // No branch of that name either.
        let listing = try GitFixtureHelper.capture(
            ["branch", "--list"],
            cwd: fixture.repoURL
        )
        #expect(!listing.contains("touch"))
    }
}
