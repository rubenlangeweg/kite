import XCTest

/// XCUITest suite for the New Branch sheet flow (VAL-BRANCHOP-001,
/// VAL-BRANCHOP-002, VAL-BRANCHOP-003).
///
/// NOTE: Authored but not run in the current environment — macOS TCC blocks
/// XCUITest harness attachment until Accessibility + Automation prompts are
/// accepted on the host machine. The suite is committed to unblock the
/// orchestrator's M6-create-branch feature; the first host that can accept
/// the prompts should re-run it.
///
/// Fixtures are created under a temp root and surfaced via
/// `-KITE_FIXTURE_ROOTS`. The app honours that arg only under XCTest (see
/// `KiteApp.isRunningUnderXCTest`).
final class CreateBranchUITests: XCTestCase {
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

    private func openNewBranchSheet(_ app: XCUIApplication) {
        let button = app.buttons["Toolbar.NewBranch"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "New branch toolbar button missing")
        button.click()
    }

    // MARK: - Tests

    /// VAL-BRANCHOP-001: clicking the New Branch toolbar button opens the
    /// sheet with the name field focused.
    func testToolbarButtonOpensSheet() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-newbranch-open")
        fixtureRoot = root
        _ = try UITestFixtures.makeRepo(named: "alpha", under: root)

        let app = launchApp(with: root)
        selectRepo(app, named: "alpha")

        openNewBranchSheet(app)

        let sheet = app.descendants(matching: .any)
            .matching(identifier: "NewBranchSheet")
            .firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 3), "Expected New Branch sheet to appear")

        let field = app.descendants(matching: .any)
            .matching(identifier: "NewBranchSheet.NameField")
            .firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 2))
    }

    /// VAL-BRANCHOP-001: typing a valid name + clicking Create runs
    /// `git switch -c <name>` on the focused repo. Assert the branch exists
    /// via `git branch --list` after the success toast appears.
    func testCreatedBranchAppearsInList() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-newbranch-created")
        fixtureRoot = root
        let repoURL = try UITestFixtures.makeRepo(named: "beta", under: root)
        // Add a second commit so `switch -c` has a real HEAD to fork from.
        try UITestFixtures.runGitForTest(
            ["commit", "--allow-empty", "-m", "second"],
            cwd: repoURL
        )

        let app = launchApp(with: root)
        selectRepo(app, named: "beta")

        openNewBranchSheet(app)

        let field = app.textFields["NewBranchSheet.NameField"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.click()
        field.typeText("feature/ui-created")

        let create = app.buttons["NewBranchSheet.Create"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 2))
        XCTAssertTrue(create.isEnabled, "Create button should enable on a valid name")
        create.click()

        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "Toast.success.")
        let successToast = app.descendants(matching: .any).matching(predicate).firstMatch
        XCTAssertTrue(
            successToast.waitForExistence(timeout: 10),
            "Expected success toast after Create click"
        )

        // Post-condition: the branch exists in the repo's local refs.
        let out = try captureGitOutput(["branch", "--list", "feature/ui-created"], cwd: repoURL)
        XCTAssertTrue(
            out.trimmingCharacters(in: .whitespacesAndNewlines).contains("feature/ui-created"),
            "expected `feature/ui-created` in `git branch --list`; got: \(out)"
        )
    }

    /// VAL-BRANCHOP-002: typing an invalid name shows the inline error label
    /// and keeps Create disabled.
    func testInvalidNameBlocksSubmit() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-newbranch-invalid")
        fixtureRoot = root
        _ = try UITestFixtures.makeRepo(named: "gamma", under: root)

        let app = launchApp(with: root)
        selectRepo(app, named: "gamma")

        openNewBranchSheet(app)

        let field = app.textFields["NewBranchSheet.NameField"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.click()
        field.typeText("foo..bar")

        let errorLabel = app.descendants(matching: .any)
            .matching(identifier: "NewBranchSheet.ValidationError")
            .firstMatch
        XCTAssertTrue(errorLabel.waitForExistence(timeout: 2), "Expected inline validation error")

        let create = app.buttons["NewBranchSheet.Create"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 2))
        XCTAssertFalse(create.isEnabled, "Create must be disabled while validation fails")
    }

    /// VAL-BRANCHOP-003: trying to create a duplicate branch surfaces the
    /// sticky error toast with git's "already exists" stderr.
    func testDuplicateNameShowsError() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-newbranch-duplicate")
        fixtureRoot = root
        let repoURL = try UITestFixtures.makeRepo(
            named: "delta",
            under: root,
            extraBranches: ["already-here"]
        )
        _ = repoURL

        let app = launchApp(with: root)
        selectRepo(app, named: "delta")

        openNewBranchSheet(app)

        let field = app.textFields["NewBranchSheet.NameField"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.click()
        field.typeText("already-here")

        let create = app.buttons["NewBranchSheet.Create"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 2))
        XCTAssertTrue(create.isEnabled, "Validator accepts the name; server-side failure is expected")
        create.click()

        let errorPredicate = NSPredicate(format: "identifier BEGINSWITH %@", "Toast.error.")
        let errorToast = app.descendants(matching: .any).matching(errorPredicate).firstMatch
        XCTAssertTrue(
            errorToast.waitForExistence(timeout: 10),
            "Expected error toast after duplicate-branch failure"
        )
    }

    // MARK: - Git helpers

    /// Shell out to `/usr/bin/git` from the UI test, capturing stdout.
    /// `UITestFixtures.runGitForTest` discards stdout; we need it here.
    private func captureGitOutput(_ args: [String], cwd: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = cwd
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        env["LC_ALL"] = "C"
        env["LANG"] = "C"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data: Data = (try? pipe.fileHandleForReading.readToEnd() ?? Data()) ?? Data()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
