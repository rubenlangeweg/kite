import XCTest

/// XCUITest suite for the working-tree status header (VAL-BRANCH-005,
/// VAL-REPO-010).
///
/// NOTE: Authored but not run in the current environment — macOS TCC blocks
/// the XCUITest harness attachment until Accessibility + Automation prompts
/// are accepted on the host machine. The suite is committed to unblock the
/// orchestrator's M3-status-header feature; the first host that can accept
/// the prompts should re-run it.
///
/// Fixtures are created under a temp root and surfaced via
/// `-KITE_FIXTURE_ROOTS`. The app honours that arg only under XCTest (see
/// `KiteApp.isRunningUnderXCTest`).
final class StatusHeaderUITests: XCTestCase {
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

    /// Write/modify a file inside the fixture repo without going through git.
    /// Used to simulate "external" filesystem changes for FSEvents tests.
    private func writeFile(at repo: URL, relative: String, contents: String) throws {
        let url = repo.appendingPathComponent(relative)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Tests

    /// VAL-BRANCH-005: the header renders the current branch name after the
    /// user selects a repo.
    func testStatusHeaderShowsCurrentBranch() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-statushdr-branch")
        fixtureRoot = root
        _ = try UITestFixtures.makeRepo(named: "alpha", under: root)

        let app = launchApp(with: root)
        selectRepo(app, named: "alpha")

        let header = app.descendants(matching: .any)
            .matching(identifier: "StatusHeader")
            .firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5), "StatusHeader never appeared")

        let branch = app.descendants(matching: .any)
            .matching(identifier: "StatusHeader.Branch")
            .firstMatch
        XCTAssertTrue(branch.waitForExistence(timeout: 5), "StatusHeader.Branch missing")
        XCTAssertEqual(branch.label, "main")
    }

    /// VAL-BRANCH-005: a repo with a worktree modification on startup
    /// surfaces the "modified" pill in the header.
    func testStatusHeaderReflectsDirtyTree() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-statushdr-dirty")
        fixtureRoot = root
        let repoURL = try UITestFixtures.makeRepo(named: "beta", under: root)

        // Create a committed file then modify it without staging so the
        // working tree is dirty at launch time. We go through `git` via
        // the UITestFixtures runner helper by writing + committing.
        try writeFile(at: repoURL, relative: "tracked.txt", contents: "v1")
        try UITestFixtures.runGitForTest(["add", "tracked.txt"], cwd: repoURL)
        try UITestFixtures.runGitForTest(["commit", "-m", "add tracked"], cwd: repoURL)
        try writeFile(at: repoURL, relative: "tracked.txt", contents: "v2-worktree")

        let app = launchApp(with: root)
        selectRepo(app, named: "beta")

        let modified = app.descendants(matching: .any)
            .matching(identifier: "StatusHeader.Modified")
            .firstMatch
        XCTAssertTrue(
            modified.waitForExistence(timeout: 5),
            "Modified pill expected on launch for dirty tree"
        )
    }

    /// VAL-REPO-010: after launch, writing a new untracked file inside the
    /// repo should cause the header to refresh (FSWatcher → focus tick →
    /// `StatusHeaderModel.reload`) within 2s.
    func testStatusHeaderRefreshesOnExternalChange() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-statushdr-refresh")
        fixtureRoot = root
        let repoURL = try UITestFixtures.makeRepo(named: "gamma", under: root)

        let app = launchApp(with: root)
        selectRepo(app, named: "gamma")

        // Clean at launch.
        let clean = app.descendants(matching: .any)
            .matching(identifier: "StatusHeader.Clean")
            .firstMatch
        XCTAssertTrue(clean.waitForExistence(timeout: 5), "Expected clean tree at launch")

        // Write an untracked file so the working tree becomes dirty.
        try writeFile(at: repoURL, relative: "newfile.txt", contents: "hello")

        let untracked = app.descendants(matching: .any)
            .matching(identifier: "StatusHeader.Untracked")
            .firstMatch
        XCTAssertTrue(
            untracked.waitForExistence(timeout: 2),
            "Expected Untracked pill after external file write within 2s (VAL-REPO-010)"
        )
    }
}
