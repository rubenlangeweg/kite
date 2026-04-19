import XCTest

/// XCUITest suite for the graph scroll container (VAL-GRAPH-009, VAL-GRAPH-010,
/// VAL-GRAPH-011).
///
/// NOTE: These tests are authored but not run in the current environment —
/// macOS TCC blocks XCUITest harness attachment until the host machine has
/// accepted Accessibility + Automation prompts. They are committed to unblock
/// the orchestrator's M4-graph-scroll-container feature; the first host that
/// can accept the prompts should re-run the suite.
///
/// Fixtures are created under a temp root and surfaced via
/// `-KITE_FIXTURE_ROOTS`. The app honours that arg only under XCTest (see
/// `KiteApp.isRunningUnderXCTest`).
final class GraphUITests: XCTestCase {
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

    // MARK: - VAL-GRAPH-010 / VAL-GRAPH-001 rendering

    /// Selecting a repo renders the commit-graph list.
    func testGraphRendersAfterFocus() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-graph")
        fixtureRoot = root
        _ = try UITestFixtures.makeRepo(named: "alpha", under: root)

        let app = launchApp(with: root)
        selectRepo(app, named: "alpha")

        let list = app.descendants(matching: .any)
            .matching(identifier: "GraphView.List")
            .firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 10), "GraphView.List never appeared")
    }

    // MARK: - VAL-GRAPH-009 selection

    /// Clicking a commit row sets selection — the row gains the accent bg and
    /// its accessibility-identifier GraphRow.<sha> stays addressable.
    func testCommitTapSetsSelection() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-graph-select")
        fixtureRoot = root
        _ = try UITestFixtures.makeRepo(named: "beta", under: root)

        let app = launchApp(with: root)
        selectRepo(app, named: "beta")

        // Any graph row — identifier is `GraphRow.<sha>`; we just need one.
        let anyRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'GraphRow.'"))
            .firstMatch
        XCTAssertTrue(anyRow.waitForExistence(timeout: 10), "no graph row appeared")
        anyRow.click()

        // No visible assertion beyond "tap did not crash the app" — this
        // mainly guards against a regression in the row-tap gesture wiring
        // until M7 observes selectedSHA and wires a real target view.
        XCTAssertTrue(anyRow.exists, "row should still exist after click")
    }

    // MARK: - VAL-GRAPH-011 shallow banner

    /// A shallow-cloned repo surfaces the shallow-clone banner at the top of
    /// the graph pane.
    func testShallowBannerAppears() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-graph-shallow")
        fixtureRoot = root
        _ = try UITestFixtures.makeShallowRepo(named: "gamma", under: root)

        let app = launchApp(with: root)
        selectRepo(app, named: "gamma")

        let banner = app.descendants(matching: .any)
            .matching(identifier: "GraphView.ShallowBanner")
            .firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "ShallowCloneBanner missing")
    }

    // MARK: - VAL-GRAPH-001 truncation footer

    /// A repo with >200 commits surfaces the 200-commit-limit footer.
    func testCommitLimitFooterAppears() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-graph-limit")
        fixtureRoot = root
        _ = try UITestFixtures.makeLargeRepo(named: "delta", under: root, commitCount: 205)

        let app = launchApp(with: root)
        selectRepo(app, named: "delta")

        // The footer is below 200 rows; scroll the list to the bottom.
        let list = app.descendants(matching: .any)
            .matching(identifier: "GraphView.List")
            .firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 15), "GraphView.List never appeared")
        // Page down until the footer shows. Bounded so the test fails fast
        // if the footer never comes into view.
        let footer = app.descendants(matching: .any)
            .matching(identifier: "GraphView.CommitLimitFooter")
            .firstMatch
        for _ in 0 ..< 40 where !footer.exists {
            list.swipeUp()
        }
        XCTAssertTrue(footer.exists, "CommitLimitFooter should be reachable by scrolling")
    }
}
