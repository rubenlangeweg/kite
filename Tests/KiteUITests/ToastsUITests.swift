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

    /// Placeholder for the real click-to-expand detail assertion (VAL-UI-005).
    /// Requires a trigger path to actually produce an error toast — deferred
    /// to M5-fetch / M5-pull-push once those surface real auth errors.
    func testErrorToastClickExpandsDetail_deferredUntilRealTriggerLands() throws {
        throw XCTSkip("No production trigger for an error toast until M5-fetch / M5-pull-push.")
    }
}
