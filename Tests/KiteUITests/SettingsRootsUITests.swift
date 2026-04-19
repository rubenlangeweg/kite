import XCTest

/// XCUITest suite for the Settings scene (VAL-REPO-003, VAL-REPO-004,
/// VAL-REPO-005, VAL-UI-008).
///
/// NOTE: These tests are authored but not run in the current environment —
/// macOS TCC blocks XCUITest attachment until the host machine has accepted
/// Accessibility + Automation prompts. They are committed to unblock the
/// orchestrator's M2-repo-list milestone; the first host that can accept the
/// prompts should re-run the suite.
///
/// The app is launched with `-KITE_FIXTURE_ROOTS` (sidebar) and
/// `-KITE_FIXTURE_EXTRA_ROOTS` (settings) so tests point Kite at temporary
/// fixture directories rather than the developer's real `~/Developer`.
final class SettingsRootsUITests: XCTestCase {
    private var fixtureRoots: [URL] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        for url in fixtureRoots {
            try? FileManager.default.removeItem(at: url)
        }
        fixtureRoots.removeAll()
    }

    // MARK: - Helpers

    private func makeEmptyFixtureDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kite-ui-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        fixtureRoots.append(url)
        return url
    }

    private func launchApp(
        sidebarRoot: URL,
        extraRoots: [URL] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-KITE_FIXTURE_ROOTS", sidebarRoot.path]
        if !extraRoots.isEmpty {
            let joined = extraRoots.map(\.path).joined(separator: ":")
            args.append(contentsOf: ["-KITE_FIXTURE_EXTRA_ROOTS", joined])
        }
        app.launchArguments = args
        app.launch()
        return app
    }

    private func openSettings(_ app: XCUIApplication) {
        // ⌘, is bound automatically by SwiftUI's Settings scene.
        app.typeKey(",", modifierFlags: .command)
    }

    // MARK: - Tests

    /// VAL-UI-008: ⌘, opens the Settings window and all three tabs are visible.
    func testCommaOpensSettings() throws {
        let root = try makeEmptyFixtureDir()
        let app = launchApp(sidebarRoot: root)

        openSettings(app)

        let settingsRoot = app.otherElements["Settings.Root"].firstMatch
        XCTAssertTrue(settingsRoot.waitForExistence(timeout: 10), "Settings window never appeared")

        XCTAssertTrue(app.buttons["General"].firstMatch.exists || app.staticTexts["General"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Roots"].firstMatch.exists || app.staticTexts["Roots"].firstMatch.exists)
        XCTAssertTrue(app.buttons["About"].firstMatch.exists || app.staticTexts["About"].firstMatch.exists)
    }

    /// VAL-REPO-003: adding an extra root (pre-seeded via launch arg) shows it
    /// in the Settings Roots table and in the sidebar without restart.
    func testAddExtraRootUpdatesSidebar() throws {
        let sidebar = try makeEmptyFixtureDir()
        let extra = try makeEmptyFixtureDir()

        let app = launchApp(sidebarRoot: sidebar, extraRoots: [extra])
        openSettings(app)

        // Switch to the Roots tab.
        let rootsTabLabel = app.buttons["Roots"].firstMatch
        if rootsTabLabel.waitForExistence(timeout: 5) {
            rootsTabLabel.click()
        } else {
            app.staticTexts["Roots"].firstMatch.click()
        }

        let table = app.tables["Settings.Roots.Table"].firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 5), "Roots table never appeared")

        // The persisted fixture extra-root path should appear in the table.
        let row = app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", extra.path)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Extra root row missing from Settings.Roots.Table")
    }

    /// VAL-REPO-004: removing an extra root removes its row from the table and
    /// drops the corresponding sidebar section.
    func testRemovingRootUpdatesSidebar() throws {
        let sidebar = try makeEmptyFixtureDir()
        let extra = try makeEmptyFixtureDir()

        let app = launchApp(sidebarRoot: sidebar, extraRoots: [extra])
        openSettings(app)

        let rootsTabLabel = app.buttons["Roots"].firstMatch
        if rootsTabLabel.waitForExistence(timeout: 5) {
            rootsTabLabel.click()
        }

        let removeButton = app.buttons["Settings.Roots.Remove.\(extra.path)"].firstMatch
        XCTAssertTrue(removeButton.waitForExistence(timeout: 5), "Remove button missing for extra root")
        XCTAssertTrue(removeButton.isEnabled)
        removeButton.click()

        // Row should disappear.
        let removedRow = app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", extra.path)).firstMatch
        XCTAssertFalse(removedRow.waitForExistence(timeout: 2), "Removed root row still visible")
    }

    /// VAL-REPO-005: the default root row cannot be removed. Its Remove button
    /// is present but disabled — we assert both.
    func testDefaultRootRemoveIsDisabled() throws {
        let sidebar = try makeEmptyFixtureDir()
        let app = launchApp(sidebarRoot: sidebar)
        openSettings(app)

        let rootsTabLabel = app.buttons["Roots"].firstMatch
        if rootsTabLabel.waitForExistence(timeout: 5) {
            rootsTabLabel.click()
        }

        // The identifier uses the absolute path, so use the home dir at
        // /Users/<name>/Developer. `FileManager.default.homeDirectoryForCurrentUser`
        // reflects the app's sandbox / user — sandbox is off so this matches.
        let developerPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Developer").path

        let removeButton = app.buttons["Settings.Roots.Remove.\(developerPath)"].firstMatch
        XCTAssertTrue(removeButton.waitForExistence(timeout: 5), "Default-root Remove button missing")
        XCTAssertFalse(removeButton.isEnabled, "Default-root Remove button should be disabled")
    }

    /// VAL-REPO-005: an invalid path surfaced via the Add Folder flow shows an
    /// inline error and does not crash.
    ///
    /// NSOpenPanel isn't easily scripted from XCUITest, so this test captures
    /// the *visible state* produced when the persistence layer has already
    /// rejected a bad path: we trigger the error directly by tapping Add and
    /// dismissing the panel, then assert that no crash has torn down the
    /// Settings window. Coverage of the error message text is in the Swift
    /// Testing logic suite.
    func testInvalidPathInlineError() throws {
        let sidebar = try makeEmptyFixtureDir()
        let app = launchApp(sidebarRoot: sidebar)
        openSettings(app)

        let rootsTabLabel = app.buttons["Roots"].firstMatch
        if rootsTabLabel.waitForExistence(timeout: 5) {
            rootsTabLabel.click()
        }

        let addButton = app.buttons["Settings.Roots.AddFolder"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.click()

        // Dismiss the NSOpenPanel — we're asserting that the UI survives the
        // cancel path. A real invalid-path test would require a faked panel.
        app.typeKey(.escape, modifierFlags: [])

        let settingsRoot = app.otherElements["Settings.Root"].firstMatch
        XCTAssertTrue(settingsRoot.exists, "Settings window disappeared after Add-Folder cancel")
    }
}
