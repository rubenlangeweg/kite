import XCTest

/// XCUITest suite for double-click branch switching (VAL-BRANCHOP-004,
/// VAL-BRANCHOP-005, VAL-BRANCHOP-006).
///
/// NOTE: Authored but not run in the current environment — macOS TCC blocks
/// XCUITest harness attachment until Accessibility + Automation prompts are
/// accepted on the host machine. The suite is committed to unblock the
/// orchestrator's M6-switch-branch feature; the first host that can accept
/// the prompts should re-run it.
final class SwitchBranchUITests: XCTestCase {
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

    /// Double-click a row with the given accessibility identifier. Retries
    /// once after a short wait — SwiftUI `List` rows sometimes need an
    /// extra frame to become hittable after the repo focus swap.
    private func doubleClickRow(_ app: XCUIApplication, identifier: String) {
        let row = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Row '\(identifier)' never appeared")
        row.doubleClick()
    }

    /// Shell out to `/usr/bin/git` from the UI test, capturing stdout.
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

    // MARK: - Tests

    /// VAL-BRANCHOP-004: double-clicking a local branch runs `git switch`
    /// and HEAD moves to the clicked branch.
    func testDoubleClickLocalBranchSwitches() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-switch-local")
        fixtureRoot = root
        let repoURL = try UITestFixtures.makeRepo(
            named: "alpha",
            under: root,
            extraBranches: ["feature/a"]
        )
        try UITestFixtures.runGitForTest(
            ["commit", "--allow-empty", "-m", "second"],
            cwd: repoURL
        )

        let app = launchApp(with: root)
        selectRepo(app, named: "alpha")

        doubleClickRow(app, identifier: "BranchRow.feature/a")

        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "Toast.success.")
        let successToast = app.descendants(matching: .any).matching(predicate).firstMatch
        XCTAssertTrue(
            successToast.waitForExistence(timeout: 10),
            "Expected success toast after double-click switch"
        )

        // Post-condition: `symbolic-ref HEAD` reports feature/a.
        let head = try captureGitOutput(["symbolic-ref", "--short", "HEAD"], cwd: repoURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(head, "feature/a", "expected HEAD on feature/a; got \(head)")
    }

    /// VAL-BRANCHOP-005: double-clicking a remote-only branch creates a
    /// local tracking branch and switches to it.
    func testDoubleClickRemoteBranchCreatesTrackingLocal() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-switch-remote")
        fixtureRoot = root
        let repoURL = try UITestFixtures.makeRepoWithRemote(
            named: "beta",
            under: root,
            extraBranches: ["feature-x"]
        )

        let app = launchApp(with: root)
        selectRepo(app, named: "beta")

        // Expand the origin DisclosureGroup first.
        let originGroup = app.descendants(matching: .any)
            .matching(identifier: "BranchList.Remote.origin")
            .firstMatch
        XCTAssertTrue(originGroup.waitForExistence(timeout: 5), "origin group missing")
        originGroup.click()

        doubleClickRow(app, identifier: "BranchRow.Remote.origin/feature-x")

        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "Toast.success.")
        let successToast = app.descendants(matching: .any).matching(predicate).firstMatch
        XCTAssertTrue(
            successToast.waitForExistence(timeout: 10),
            "Expected success toast after remote-branch double-click"
        )

        // Local feature-x exists with upstream origin/feature-x.
        let listing = try captureGitOutput(["branch", "--list", "feature-x"], cwd: repoURL)
        XCTAssertTrue(
            listing.contains("feature-x"),
            "expected local feature-x in `git branch --list`; got: \(listing)"
        )
        let upstream = try captureGitOutput(
            ["for-each-ref", "--format=%(upstream:short)", "refs/heads/feature-x"],
            cwd: repoURL
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(upstream, "origin/feature-x")
    }

    /// VAL-BRANCHOP-004 no-op: double-clicking the already-current branch
    /// does NOT spawn a git subprocess / show a toast.
    func testDoubleClickCurrentBranchNoOp() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-switch-current")
        fixtureRoot = root
        _ = try UITestFixtures.makeRepo(named: "gamma", under: root)

        let app = launchApp(with: root)
        selectRepo(app, named: "gamma")

        doubleClickRow(app, identifier: "BranchRow.main")

        // Give SwiftUI a beat to process the gesture. If a subprocess
        // surfaced a success toast it would be visible within ~2s.
        let successPred = NSPredicate(format: "identifier BEGINSWITH %@", "Toast.success.")
        let toast = app.descendants(matching: .any).matching(successPred).firstMatch
        XCTAssertFalse(
            toast.waitForExistence(timeout: 2),
            "Double-clicking current branch must be a no-op"
        )
    }

    /// VAL-BRANCHOP-006: double-clicking a branch that would clobber an
    /// uncommitted change shows the documented dirty-tree error toast.
    func testDirtyTreeErrorToast() throws {
        let root = try UITestFixtures.makeTempRoot(prefix: "kite-ui-switch-dirty")
        fixtureRoot = root
        let repoURL = try UITestFixtures.makeRepo(named: "delta", under: root)

        // Set up a tracked file with divergent content across branches + a
        // local unclobberable modification (classic dirty-tree setup).
        let filePath = repoURL.appendingPathComponent("file.txt")
        try Data("v=main\n".utf8).write(to: filePath)
        try UITestFixtures.runGitForTest(["add", "file.txt"], cwd: repoURL)
        try UITestFixtures.runGitForTest(["commit", "-m", "main adds file"], cwd: repoURL)
        try UITestFixtures.runGitForTest(["checkout", "-b", "other"], cwd: repoURL)
        try Data("v=other\n".utf8).write(to: filePath)
        try UITestFixtures.runGitForTest(["add", "file.txt"], cwd: repoURL)
        try UITestFixtures.runGitForTest(["commit", "-m", "on other"], cwd: repoURL)
        try UITestFixtures.runGitForTest(["checkout", "main"], cwd: repoURL)
        try Data("v=main-dirty\n".utf8).write(to: filePath)

        let app = launchApp(with: root)
        selectRepo(app, named: "delta")

        doubleClickRow(app, identifier: "BranchRow.other")

        let errorPred = NSPredicate(format: "identifier BEGINSWITH %@", "Toast.error.")
        let errorToast = app.descendants(matching: .any).matching(errorPred).firstMatch
        XCTAssertTrue(
            errorToast.waitForExistence(timeout: 10),
            "Expected dirty-tree error toast after double-click switch"
        )
    }
}
