import XCTest

/// XCUITest suite for the read-only working-copy diff pane (VAL-DIFF-001,
/// VAL-DIFF-002, VAL-DIFF-007).
///
/// NOTE: Authored but not run in the current environment — macOS TCC still
/// blocks the XCUITest harness attachment until Accessibility + Automation
/// prompts are accepted on the host machine. The suite is committed to
/// unblock the orchestrator's M7-uncommitted-diff feature; the first host
/// that can accept the prompts should re-run it alongside the other
/// KiteUITests suites.
///
/// Fixtures are created under a temp root and surfaced via
/// `-KITE_FIXTURE_ROOTS`. The app honours that arg only under XCTest (see
/// `KiteApp.isRunningUnderXCTest`).
final class UncommittedDiffUITests: XCTestCase {
    private var fixtureRoot: URL?

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        if let root = fixtureRoot {
            try? FileManager.default.removeItem(at: root)
            fixtureRoot = nil
        }
    }

    // MARK: - Helpers

    private func launchApp(with root: URL) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-KITE_FIXTURE_ROOTS", root.path]
        app.launch()
        return app
    }

    private func selectRepo(_ app: XCUIApplication, named name: String) {
        let row = app.staticTexts[name].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Repo row '\(name)' never appeared")
        row.click()
    }

    private func writeFile(at repo: URL, relative: String, contents: String) throws {
        let url = repo.appendingPathComponent(relative)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Tests

    /// VAL-DIFF-001: with a focused repo that has an unstaged modification,
    /// the "Unstaged changes" section header should appear in the diff pane.
    func testDiffShowsAfterFocus() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-diff-unstaged")
        fixtureRoot = root
        let repoURL = try UITestFixtures.makeRepo(named: "alpha", under: root)

        // Seed + commit a tracked file, then modify it on disk so `git diff`
        // has something to report once the app focuses the repo.
        try writeFile(at: repoURL, relative: "tracked.txt", contents: "v1")
        try UITestFixtures.runGitForTest(["add", "tracked.txt"], cwd: repoURL)
        try UITestFixtures.runGitForTest(["commit", "-m", "add tracked"], cwd: repoURL)
        try writeFile(at: repoURL, relative: "tracked.txt", contents: "v2-worktree")

        let app = launchApp(with: root)
        selectRepo(app, named: "alpha")

        let diff = app.descendants(matching: .any)
            .matching(identifier: "UncommittedDiff")
            .firstMatch
        XCTAssertTrue(diff.waitForExistence(timeout: 5), "UncommittedDiff pane never appeared")

        let unstagedHeader = app.descendants(matching: .any)
            .matching(identifier: "UncommittedDiff.Section.Unstaged changes")
            .firstMatch
        XCTAssertTrue(
            unstagedHeader.waitForExistence(timeout: 5),
            "Unstaged-changes section header missing for repo with a modified tracked file"
        )
    }

    /// VAL-DIFF-002: a clean working tree renders the empty state with its
    /// `ContentUnavailableView` label.
    func testCleanTreeEmptyState() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-diff-clean")
        fixtureRoot = root
        _ = try UITestFixtures.makeRepo(named: "beta", under: root)

        let app = launchApp(with: root)
        selectRepo(app, named: "beta")

        let empty = app.descendants(matching: .any)
            .matching(identifier: "UncommittedDiff.Empty")
            .firstMatch
        XCTAssertTrue(
            empty.waitForExistence(timeout: 5),
            "Expected the clean-tree empty state (UncommittedDiff.Empty) to appear"
        )
    }

    /// VAL-DIFF-007: strictly read-only. No "Stage", "Discard" or "Revert"
    /// button should exist anywhere under the diff pane. This suite is the
    /// canonical evidence for that assertion.
    func testNoDestructiveActions() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-diff-readonly")
        fixtureRoot = root
        let repoURL = try UITestFixtures.makeRepo(named: "gamma", under: root)

        // Create a mixed state (one staged mod + one unstaged mod) so the
        // pane is populated and each hypothetical destructive button would
        // have *something* to act on.
        try writeFile(at: repoURL, relative: "a.txt", contents: "a-v1")
        try writeFile(at: repoURL, relative: "b.txt", contents: "b-v1")
        try UITestFixtures.runGitForTest(["add", "a.txt", "b.txt"], cwd: repoURL)
        try UITestFixtures.runGitForTest(["commit", "-m", "seed a + b"], cwd: repoURL)
        try writeFile(at: repoURL, relative: "a.txt", contents: "a-v2")
        try UITestFixtures.runGitForTest(["add", "a.txt"], cwd: repoURL)
        try writeFile(at: repoURL, relative: "b.txt", contents: "b-v2")

        let app = launchApp(with: root)
        selectRepo(app, named: "gamma")

        let diff = app.descendants(matching: .any)
            .matching(identifier: "UncommittedDiff")
            .firstMatch
        XCTAssertTrue(diff.waitForExistence(timeout: 5), "UncommittedDiff pane never appeared")

        // None of these destructive button labels may exist anywhere in the
        // diff pane's subtree. Matching is case-sensitive; this is the exact
        // prefix-free check VAL-DIFF-007 demands.
        for label in ["Stage", "Unstage", "Discard", "Revert", "Reset"] {
            let match = diff.buttons[label]
            XCTAssertFalse(
                match.exists,
                "VAL-DIFF-007 violation: destructive button '\(label)' found in diff pane"
            )
        }
    }
}
