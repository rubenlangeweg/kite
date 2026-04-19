import Foundation

/// Test-only helper for setting up fixture repositories. Lives under the
/// Tests target so fixtures do not ship in the app.
enum GitFixtureHelper {
    /// Generate a unique scratch URL under the system temp directory.
    static func tempURL() -> URL {
        FileManager.default
            .temporaryDirectory
            .appendingPathComponent("kite-tests-\(UUID().uuidString)", isDirectory: true)
    }

    /// Initialise a clean repo at `dir` with a single empty commit so `HEAD`
    /// is valid. Configures user.email / user.name locally to avoid depending
    /// on the developer's global git identity.
    static func cleanRepo(at dir: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        try runGit(["init", "-b", "main"], cwd: dir)
        try runGit(["config", "user.email", "tests@kite.local"], cwd: dir)
        try runGit(["config", "user.name", "Kite Tests"], cwd: dir)
        try runGit(["config", "commit.gpgsign", "false"], cwd: dir)
        try runGit(["commit", "--allow-empty", "-m", "initial"], cwd: dir)
    }

    /// Best-effort cleanup. Ignores failures (typical for tests that already
    /// succeeded in removing the fixture).
    static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Private

    private static func runGit(_ args: [String], cwd: URL) throws {
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
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(
                domain: "GitFixtureHelper",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "git \(args.joined(separator: " ")) failed"]
            )
        }
    }
}
