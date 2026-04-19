import XCTest

final class SmokeUITest: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchesAndShowsWindow() {
        let app = XCUIApplication()
        app.launch()
        // Wait for the app to register a window with the UI testing runtime.
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "Kite main window did not appear within 10s")
    }
}
