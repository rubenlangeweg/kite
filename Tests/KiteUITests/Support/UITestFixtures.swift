import Foundation

/// Test-only helper building fixture repositories for XCUITest runs.
///
/// XCUITests point the app at a temp root via `-KITE_FIXTURE_ROOTS`; this
/// helper provisions the repos beneath that root. Each fixture method
/// returns the generated repo URL so the test can inspect it after the app
/// launches. Tests are responsible for tearing down the root via
/// `FileManager.default.removeItem` on teardown.
///
/// Kept parallel to `GitFixtureHelper` (KiteTests target) so the UI target's
/// sandboxing rules don't force a cross-target dependency.
enum UITestFixtures {
    /// Create an empty repo directory containing a single `main` branch and
    /// one initial commit.
    @discardableResult
    static func makeRepo(
        named name: String,
        under root: URL,
        extraBranches: [String] = []
    ) throws -> URL {
        let repoURL = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], cwd: repoURL)
        try runGit(["config", "user.email", "tests@kite.local"], cwd: repoURL)
        try runGit(["config", "user.name", "Kite Tests"], cwd: repoURL)
        try runGit(["config", "commit.gpgsign", "false"], cwd: repoURL)
        try runGit(["commit", "--allow-empty", "-m", "initial"], cwd: repoURL)
        for branch in extraBranches {
            try runGit(["branch", branch], cwd: repoURL)
        }
        return repoURL
    }

    /// Create a fixture with a remote: a bare `<name>.git` plus a working
    /// checkout `<name>` that pushes `main` to it. Returns the working URL.
    @discardableResult
    static func makeRepoWithRemote(
        named name: String,
        under root: URL,
        extraBranches: [String] = []
    ) throws -> URL {
        let bareURL = root.appendingPathComponent("\(name).git")
        try runGit(["init", "--bare", "-b", "main", bareURL.path], cwd: root)

        let workURL = try makeRepo(named: name, under: root, extraBranches: extraBranches)
        try runGit(["remote", "add", "origin", bareURL.path], cwd: workURL)
        try runGit(["push", "-u", "origin", "main"], cwd: workURL)
        for branch in extraBranches {
            try runGit(["push", "origin", branch], cwd: workURL)
        }
        return workURL
    }

    /// Create a repo with a second commit then detach HEAD to the first
    /// commit. Returns the repo URL.
    @discardableResult
    static func makeDetachedRepo(named name: String, under root: URL) throws -> URL {
        let repoURL = try makeRepo(named: name, under: root)
        try runGit(["commit", "--allow-empty", "-m", "second"], cwd: repoURL)
        try runGit(["switch", "--detach", "HEAD^"], cwd: repoURL)
        return repoURL
    }

    /// Create a shallow clone: build a fresh "origin" repo with `commitCount`
    /// commits, then `git clone --depth=1` into `<name>`. Returns the shallow
    /// checkout URL.
    @discardableResult
    static func makeShallowRepo(
        named name: String,
        under root: URL,
        commitCount: Int = 5
    ) throws -> URL {
        let originURL = root.appendingPathComponent("\(name)-origin")
        try makeRepo(named: "\(name)-origin", under: root)
        for index in 0 ..< max(0, commitCount - 1) {
            try runGit(["commit", "--allow-empty", "-m", "c-\(index)"], cwd: originURL)
        }

        let shallowURL = root.appendingPathComponent(name)
        // file:// is required because local (non-file://) clones ignore
        // --depth and print a warning, leaving the clone non-shallow.
        try runGit(["clone", "--depth=1", "file://\(originURL.path)", shallowURL.path], cwd: root)
        return shallowURL
    }

    /// Create a repo with more than 200 commits so the graph hits its cap.
    @discardableResult
    static func makeLargeRepo(named name: String, under root: URL, commitCount: Int = 205) throws -> URL {
        let repoURL = try makeRepo(named: name, under: root)
        for index in 0 ..< max(0, commitCount - 1) {
            try runGit(["commit", "--allow-empty", "-m", "c-\(index)"], cwd: repoURL)
        }
        return repoURL
    }

    /// Create a fresh root directory under the system temp dir. Caller owns
    /// cleanup.
    static func makeTempRoot(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Exposed variant of the git runner for tests that need to shell out
    /// against a fixture repo after it has been created (e.g. staging a
    /// commit before launching the app). Uses the same hardened env as the
    /// private `runGit`.
    static func runGitForTest(_ args: [String], cwd: URL) throws {
        try runGit(args, cwd: cwd)
    }

    // MARK: - Private

    private static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        env["LC_ALL"] = "C"
        env["LANG"] = "C"
        return env
    }

    private static func runGit(_ args: [String], cwd: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = cwd
        process.environment = environment()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(
                domain: "UITestFixtures",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "git \(args.joined(separator: " ")) failed"]
            )
        }
    }
}
