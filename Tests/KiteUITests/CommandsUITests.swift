import XCTest

/// XCUITest suite covering the Commands menu + keyboard shortcuts
/// (VAL-UI-002, VAL-UI-003, VAL-UI-009).
///
/// NOTE: Authored but not run in the current environment — macOS TCC blocks
/// XCUITest harness attachment until Accessibility + Automation prompts are
/// accepted on the host machine (see AGENTS.md §"Installed dev tools" and
/// the skip-list note). Each test body calls `XCTSkip` with the reason so
/// `xcodebuild test` won't mark them as failed on CI until the host
/// accepts the prompts.
///
/// Once the prompts are accepted, the author should replace the `XCTSkip`
/// preamble with real launchArg fixtures + menu navigation / keyboard
/// press assertions. Shape intentionally mirrors `FetchUITests` and
/// `CreateBranchUITests` — spawn a fixture root, launch the app with
/// `-KITE_FIXTURE_ROOTS <path>`, select the fixture repo, then exercise
/// each shortcut.
final class CommandsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// ⌘R fires the Repository > Refresh menu action.
    func testRefreshShortcutFiresRepositoryRefresh() throws {
        try XCTSkipIf(true, "M8-commands-and-menu: stub pending host TCC grants for XCUITest")
    }

    /// ⌘⇧F fires the Repository > Fetch menu action against the focused repo.
    func testFetchShortcutFiresRepositoryFetch() throws {
        try XCTSkipIf(true, "M8-commands-and-menu: stub pending host TCC grants for XCUITest")
    }

    /// ⌘⇧P fires the Repository > Pull (fast-forward only) menu action.
    func testPullShortcutFiresRepositoryPull() throws {
        try XCTSkipIf(true, "M8-commands-and-menu: stub pending host TCC grants for XCUITest")
    }

    /// ⌘⇧K fires the Repository > Push menu action.
    func testPushShortcutFiresRepositoryPush() throws {
        try XCTSkipIf(true, "M8-commands-and-menu: stub pending host TCC grants for XCUITest")
    }

    /// ⌘⇧N opens the NewBranchSheet by bumping `AppCommands.newBranchRequest`
    /// which the toolbar's `NewBranchButton` observes.
    func testNewBranchShortcutOpensSheet() throws {
        try XCTSkipIf(true, "M8-commands-and-menu: stub pending host TCC grants for XCUITest")
    }

    /// VAL-UI-009: ⌘N spawns a second independent main window via
    /// `openWindow(id: "main")`. Both windows must remain responsive.
    func testNewWindowShortcutOpensSecondWindow() throws {
        try XCTSkipIf(true, "M8-commands-and-menu: stub pending host TCC grants for XCUITest")
    }

    /// ⌘, (SwiftUI-auto-wired) continues to open the Settings scene even
    /// with `KiteCommands` installed — we must not accidentally have
    /// replaced the Settings group.
    func testSettingsShortcutStillOpensSettings() throws {
        try XCTSkipIf(true, "M8-commands-and-menu: stub pending host TCC grants for XCUITest")
    }
}
