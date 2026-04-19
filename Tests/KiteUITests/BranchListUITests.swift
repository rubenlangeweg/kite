import XCTest

/// XCUITest suite for the branch list middle-column pane (VAL-BRANCH-001,
/// VAL-BRANCH-002, VAL-BRANCH-004).
///
/// NOTE: These tests are authored but not run in the current environment —
/// macOS TCC blocks XCUITest harness attachment until the host machine has
/// accepted Accessibility + Automation prompts. They are committed to
/// unblock the orchestrator's M3-branch-list feature; the first host that
/// can accept the prompts should re-run the suite.
///
/// Fixtures are created under a temp root and surfaced via
/// `-KITE_FIXTURE_ROOTS`. The app honours that arg only under XCTest (see
/// `KiteApp.isRunningUnderXCTest`).
final class BranchListUITests: XCTestCase {
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

    // MARK: - Tests

    /// VAL-BRANCH-001: current branch row is visible after selecting a repo.
    func testBranchListShowsCurrentBranch() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-branch")
        fixtureRoot = root
        _ = try UITestFixtures.makeRepo(named: "alpha", under: root, extraBranches: ["feature/a"])

        let app = launchApp(with: root)
        selectRepo(app, named: "alpha")

        let list = app.scrollViews.matching(identifier: "BranchList.List").firstMatch
        XCTAssertTrue(
            list.waitForExistence(timeout: 5)
                || app.otherElements["BranchList.List"].firstMatch.waitForExistence(timeout: 5),
            "BranchList.List never appeared"
        )

        let mainRow = app.descendants(matching: .any)
            .matching(identifier: "BranchRow.main")
            .firstMatch
        XCTAssertTrue(mainRow.waitForExistence(timeout: 5), "'main' BranchRow missing")

        let featureRow = app.descendants(matching: .any)
            .matching(identifier: "BranchRow.feature/a")
            .firstMatch
        XCTAssertTrue(featureRow.waitForExistence(timeout: 5), "'feature/a' BranchRow missing")
    }

    /// VAL-BRANCH-004: a detached-HEAD repo surfaces the detached banner.
    func testDetachedHeadShown() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-detached")
        fixtureRoot = root
        _ = try UITestFixtures.makeDetachedRepo(named: "delta", under: root)

        let app = launchApp(with: root)
        selectRepo(app, named: "delta")

        let banner = app.descendants(matching: .any)
            .matching(identifier: "BranchList.DetachedHeadBanner")
            .firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "Detached HEAD banner missing")
    }

    /// VAL-BRANCH-002: a repo with an origin remote renders an origin
    /// DisclosureGroup in the branch list.
    func testRemoteBranchesGroupedByRemote() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-remote")
        fixtureRoot = root
        _ = try UITestFixtures.makeRepoWithRemote(
            named: "epsilon",
            under: root,
            extraBranches: ["feature/x"]
        )

        let app = launchApp(with: root)
        selectRepo(app, named: "epsilon")

        let originGroup = app.descendants(matching: .any)
            .matching(identifier: "BranchList.Remote.origin")
            .firstMatch
        XCTAssertTrue(originGroup.waitForExistence(timeout: 5), "origin DisclosureGroup missing")
    }
}
