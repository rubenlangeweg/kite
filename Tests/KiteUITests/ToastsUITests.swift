import XCTest

/// XCUITest surface for toast infrastructure. In M5-toast-infrastructure
/// we have no production trigger path — toasts are exercised by later
/// M5 features (fetch, pull/push, auto-fetch). This file is a minimal
/// smoke placeholder so the test bundle remains wired. M5-fetch /
/// M5-pull-push fill out real triggers; M5-auto-fetch extends.
///
/// For now we only assert the toast host overlay is part of the
/// accessibility tree so later features can query for `Toast.Host`
/// without rediscovering it. The host stays empty until something
/// enqueues a toast.
final class ToastsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The toast host overlay is attached to the root view and visible in
    /// the accessibility tree even when no toasts are queued. Later
    /// XCUITests (fetch/pull/push) rely on this identifier to scope their
    /// assertions.
    func testToastHostOverlayExists() {
        let app = XCUIApplication()
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "Kite main window did not appear")

        // `Toast.Host` accessibility identifier lives on the ToastHostView
        // VStack. It's always present in the view hierarchy (empty children
        // when no toasts are queued). Descendants query is tolerant of the
        // overlay being attached deeply inside the NavigationSplitView.
        let host = window.descendants(matching: .any)["Toast.Host"]
        XCTAssertTrue(host.waitForExistence(timeout: 5), "Toast.Host overlay not found in accessibility tree")
    }

    /// VAL-UI-005: clicking an error toast expands a detail panel with the
    /// captured git stderr. The trigger path is a failing fetch — we create
    /// a working clone whose bare remote is then deleted out from under it,
    /// click the Fetch toolbar button, and assert the resulting red sticky
    /// toast expands on tap.
    func testErrorToastClickExpandsDetail() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-toast-detail")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        _ = try UITestFixtures.makeRepoWithRemote(named: "toast-detail", under: root)
        try FileManager.default.removeItem(at: root.appendingPathComponent("toast-detail.git"))

        let app = XCUIApplication()
        app.launchArguments = ["-KITE_FIXTURE_ROOTS", root.path]
        app.launch()

        let repoRow = app.staticTexts["toast-detail"].firstMatch
        XCTAssertTrue(repoRow.waitForExistence(timeout: 10), "fixture repo row missing")
        repoRow.click()

        let fetchButton = app.buttons["Toolbar.Fetch"].firstMatch
        XCTAssertTrue(fetchButton.waitForExistence(timeout: 5), "Fetch button missing")
        fetchButton.click()

        let errorPredicate = NSPredicate(format: "identifier BEGINSWITH %@", "Toast.error.")
        let errorToast = app.descendants(matching: .any).matching(errorPredicate).firstMatch
        XCTAssertTrue(errorToast.waitForExistence(timeout: 10), "error toast never appeared")

        errorToast.click()
        let detail = app.descendants(matching: .any)
            .matching(identifier: "Toast.Detail")
            .firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 3), "Toast.Detail did not appear after tap")
    }
}
