import XCTest

/// XCUITest suite for the toolbar Fetch button (VAL-NET-001, VAL-NET-005,
/// VAL-BRANCH-006).
///
/// NOTE: Authored but not run in the current environment — macOS TCC blocks
/// XCUITest harness attachment until Accessibility + Automation prompts are
/// accepted on the host machine. The suite is committed to unblock the
/// orchestrator's M5-fetch feature; the first host that can accept the
/// prompts should re-run it.
///
/// Fixtures are created under a temp root and surfaced via
/// `-KITE_FIXTURE_ROOTS`. The app honours that arg only under XCTest (see
/// `KiteApp.isRunningUnderXCTest`).
final class FetchUITests: XCTestCase {
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

    /// VAL-NET-001 / VAL-NET-005: clicking the Fetch toolbar button on a
    /// repo with a reachable remote produces a green success toast.
    func testFetchButtonFires() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-fetch-success")
        fixtureRoot = root
        // makeRepoWithRemote sets up a bare + working clone with
        // `origin` pointing at the bare. A fetch should succeed with
        // no incoming changes — still a successful op.
        _ = try UITestFixtures.makeRepoWithRemote(named: "omega", under: root)

        let app = launchApp(with: root)
        selectRepo(app, named: "omega")

        let fetchButton = app.buttons["Toolbar.Fetch"].firstMatch
        XCTAssertTrue(fetchButton.waitForExistence(timeout: 5), "Fetch toolbar button missing")
        fetchButton.click()

        // Success toasts have an accessibility identifier shaped like
        // `Toast.success.<uuid>`. Match by prefix via an NSPredicate.
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "Toast.success.")
        let successToast = app.descendants(matching: .any).matching(predicate).firstMatch
        XCTAssertTrue(
            successToast.waitForExistence(timeout: 10),
            "Expected success toast after Fetch click"
        )
    }

    /// VAL-NET-001 error path / VAL-UI-005: a repo whose remote has been
    /// deleted produces a sticky red error toast. The toast carries a
    /// dismiss (✕) button (sticky) and expands to show captured stderr on
    /// tap.
    func testFetchErrorShowsSticky() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-fetch-error")
        fixtureRoot = root
        _ = try UITestFixtures.makeRepoWithRemote(named: "kappa", under: root)

        // Delete the bare remote — the working clone's `origin` URL now
        // points nowhere.
        let bareURL = root.appendingPathComponent("kappa.git")
        try FileManager.default.removeItem(at: bareURL)

        let app = launchApp(with: root)
        selectRepo(app, named: "kappa")

        let fetchButton = app.buttons["Toolbar.Fetch"].firstMatch
        XCTAssertTrue(fetchButton.waitForExistence(timeout: 5), "Fetch toolbar button missing")
        fetchButton.click()

        let errorPredicate = NSPredicate(format: "identifier BEGINSWITH %@", "Toast.error.")
        let errorToast = app.descendants(matching: .any).matching(errorPredicate).firstMatch
        XCTAssertTrue(
            errorToast.waitForExistence(timeout: 10),
            "Expected error toast after failing fetch"
        )

        // Sticky error toasts expose a dismiss button (Toast.DismissButton).
        let dismiss = app.buttons["Toast.DismissButton"].firstMatch
        XCTAssertTrue(
            dismiss.waitForExistence(timeout: 2),
            "Sticky error toast must expose a dismiss ✕ button"
        )

        // Tap the toast row to expand its detail panel (VAL-UI-005).
        errorToast.click()
        let detail = app.descendants(matching: .any)
            .matching(identifier: "Toast.Detail")
            .firstMatch
        XCTAssertTrue(
            detail.waitForExistence(timeout: 3),
            "Tapping an error toast should expand the detail panel"
        )
    }
}
