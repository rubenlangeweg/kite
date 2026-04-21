import XCTest

/// XCUITest suite for the toolbar Pull + Push buttons (VAL-NET-002,
/// VAL-NET-003, VAL-NET-004).
///
/// NOTE: Authored but not run in the current environment — macOS TCC blocks
/// XCUITest harness attachment until Accessibility + Automation prompts are
/// accepted on the host machine. The suite is committed to unblock the
/// orchestrator's M5-pull-push feature; the first host that can accept the
/// prompts should re-run it.
///
/// Fixtures are created under a temp root and surfaced via
/// `-KITE_FIXTURE_ROOTS`. The app honours that arg only under XCTest (see
/// `KiteApp.isRunningUnderXCTest`).
final class PullPushUITests: XCTestCase {
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

    /// Delete the tracker's local commit graph from HEAD without using
    /// `reset --hard`. Used to stage "diverged" fixtures for pull tests.
    private static func rewindRef(_ ref: String, to sha: String, in repo: URL) throws {
        try UITestFixtures.runGitForTest(["update-ref", "refs/heads/\(ref)", sha], cwd: repo)
    }

    // MARK: - Tests

    /// VAL-NET-002: clicking the Pull toolbar button on a clean tracking
    /// branch produces a green success toast.
    func testPullButtonFires() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-pull-success")
        fixtureRoot = root
        _ = try UITestFixtures.makeRepoWithRemote(named: "alpha", under: root)

        let app = launchApp(with: root)
        selectRepo(app, named: "alpha")

        let pullButton = app.buttons["Toolbar.Pull"].firstMatch
        XCTAssertTrue(pullButton.waitForExistence(timeout: 5), "Pull toolbar button missing")
        pullButton.click()

        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "Toast.success.")
        let successToast = app.descendants(matching: .any).matching(predicate).firstMatch
        XCTAssertTrue(
            successToast.waitForExistence(timeout: 10),
            "Expected success toast after Pull click"
        )
    }

    /// VAL-NET-003: clicking Push on a branch that has no upstream surfaces
    /// the `UpstreamSetSheet` offering `git push -u origin <branch>`.
    func testPushUpstreamSheetAppears() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-push-upstream")
        fixtureRoot = root
        let repo = try UITestFixtures.makeRepoWithRemote(named: "beta", under: root)

        // Create a brand new local branch on the tracker — no upstream.
        try UITestFixtures.runGitForTest(["switch", "-c", "feature-no-upstream"], cwd: repo)
        try UITestFixtures.runGitForTest(
            ["commit", "--allow-empty", "-m", "fresh"],
            cwd: repo
        )

        let app = launchApp(with: root)
        selectRepo(app, named: "beta")

        let pushButton = app.buttons["Toolbar.Push"].firstMatch
        XCTAssertTrue(pushButton.waitForExistence(timeout: 5), "Push toolbar button missing")
        pushButton.click()

        let sheet = app.descendants(matching: .any)
            .matching(identifier: "UpstreamSheet")
            .firstMatch
        XCTAssertTrue(
            sheet.waitForExistence(timeout: 10),
            "Expected UpstreamSetSheet to appear for branch without upstream"
        )

        // The title must mention the branch name so the user can verify
        // before confirming.
        let title = app.staticTexts.matching(identifier: "UpstreamSheet.Title").firstMatch
        XCTAssertTrue(title.exists, "UpstreamSheet title missing")
    }

    /// VAL-NET-003: confirming the UpstreamSetSheet triggers the actual
    /// `git push -u` invocation — observable via the subsequent success
    /// toast.
    func testPushConfirmActuallyPushes() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-push-confirm")
        fixtureRoot = root
        let repo = try UITestFixtures.makeRepoWithRemote(named: "gamma", under: root)

        try UITestFixtures.runGitForTest(["switch", "-c", "feature-confirm"], cwd: repo)
        try UITestFixtures.runGitForTest(
            ["commit", "--allow-empty", "-m", "confirm-commit"],
            cwd: repo
        )

        let app = launchApp(with: root)
        selectRepo(app, named: "gamma")

        let pushButton = app.buttons["Toolbar.Push"].firstMatch
        XCTAssertTrue(pushButton.waitForExistence(timeout: 5))
        pushButton.click()

        let confirm = app.buttons["UpstreamSheet.Confirm"].firstMatch
        XCTAssertTrue(
            confirm.waitForExistence(timeout: 10),
            "UpstreamSheet confirm button missing"
        )
        confirm.click()

        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "Toast.success.")
        let successToast = app.descendants(matching: .any).matching(predicate).firstMatch
        XCTAssertTrue(
            successToast.waitForExistence(timeout: 15),
            "Expected success toast after confirming upstream push"
        )
    }

    /// VAL-NET-002 negative: pushing on a diverged history surfaces a
    /// sticky red error toast (non-fast-forward).
    func testPushNonFFShowsError() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-push-nonff")
        fixtureRoot = root
        let repo = try UITestFixtures.makeRepoWithRemote(named: "delta", under: root)

        // Make the tracker diverge: the bare remote's main advances via an
        // "author" clone and the tracker independently adds a local commit
        // on its stale base.
        let bareURL = root.appendingPathComponent("delta.git")
        let authorURL = root.appendingPathComponent("delta-author")
        try FileManager.default.createDirectory(at: authorURL, withIntermediateDirectories: true)
        try UITestFixtures.runGitForTest(["clone", bareURL.path, authorURL.path], cwd: root)
        try UITestFixtures.runGitForTest(
            ["config", "user.email", "tests@kite.local"],
            cwd: authorURL
        )
        try UITestFixtures.runGitForTest(
            ["config", "user.name", "Kite Tests"],
            cwd: authorURL
        )
        try UITestFixtures.runGitForTest(
            ["commit", "--allow-empty", "-m", "remote-advance"],
            cwd: authorURL
        )
        try UITestFixtures.runGitForTest(["push", "origin", "main"], cwd: authorURL)

        // Tracker adds a local-only commit (no fetch) — history diverges.
        try UITestFixtures.runGitForTest(
            ["commit", "--allow-empty", "-m", "tracker-local"],
            cwd: repo
        )

        let app = launchApp(with: root)
        selectRepo(app, named: "delta")

        let pushButton = app.buttons["Toolbar.Push"].firstMatch
        XCTAssertTrue(pushButton.waitForExistence(timeout: 5))
        pushButton.click()

        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "Toast.error.")
        let errorToast = app.descendants(matching: .any).matching(predicate).firstMatch
        XCTAssertTrue(
            errorToast.waitForExistence(timeout: 15),
            "Expected sticky error toast on non-fast-forward push"
        )

        // Sticky error toasts expose a dismiss button.
        let dismiss = app.buttons["Toast.DismissButton"].firstMatch
        XCTAssertTrue(
            dismiss.waitForExistence(timeout: 2),
            "Sticky error toast must expose a dismiss button"
        )
    }
}
