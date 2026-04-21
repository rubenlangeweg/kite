import XCTest

/// XCUITest surface for the selected-commit diff pane (VAL-GRAPH-009,
/// VAL-DIFF-003).
///
/// NOTE: These tests are authored but not run in the current environment —
/// macOS TCC blocks XCUITest harness attachment until the host machine has
/// accepted Accessibility + Automation prompts. They are committed to
/// unblock scrutiny-validator-diff; the first host that can accept the
/// prompts should re-run the suite.
///
/// Pattern mirrors `BranchListUITests` + `ToastsUITests`: stubs throw
/// `XCTSkip` with descriptive comments so the suite lights up yellow in
/// Xcode rather than silently missing coverage.
final class CommitDiffUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// VAL-GRAPH-009: clicking a commit row in the graph opens the
    /// CommitHeader panel in the right pane.
    ///
    /// Flow:
    ///   - Launch Kite with `-KITE_FIXTURE_ROOTS` pointing at a pre-built
    ///     repo with ≥1 commit (via UITestFixtures.makeRepo).
    ///   - Select the repo row in the sidebar.
    ///   - Click a row in the `GraphView` list.
    ///   - Assert the `CommitHeader` accessibility identifier appears in the
    ///     right pane.
    func testClickCommitOpensDiffPane() throws {
        throw XCTSkip("TCC Automation permission required on this host; see AGENTS.md skip-list.")
    }

    /// VAL-DIFF-003: clicking a second commit switches the diff pane to
    /// that commit's `git show` output — the previous commit's header +
    /// files are replaced (not appended).
    func testClickAnotherCommitSwitchesDiff() throws {
        throw XCTSkip("Pending TCC grant.")
    }

    /// DiffPaneRouter focus-swap contract: switching the focused repo
    /// clears the `DiffPaneSelection.selectedSHA` so the router falls back
    /// to `UncommittedDiffView` for the newly focused repo (carrying a
    /// stale SHA across repo switches would show the wrong commit).
    func testDiffPaneClearsOnFocusChange() throws {
        throw XCTSkip("Pending TCC grant.")
    }
}
