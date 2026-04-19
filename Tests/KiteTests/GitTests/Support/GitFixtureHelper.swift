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

    /// Run a git command inside a fixture and return its stdout as a String.
    /// Used by parser tests that want real git output rather than a
    /// hand-crafted fixture string.
    static func capture(_ args: [String], cwd: URL) throws -> String {
        let result = try captureData(args, cwd: cwd)
        return String(data: result, encoding: .utf8) ?? ""
    }

    /// Like `capture` but returns raw Data — use for `-z` outputs where
    /// embedded NULs would confuse a String-first path (even though Swift
    /// Strings can hold NULs, Data round-trips are clearer for tests).
    static func captureData(_ args: [String], cwd: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = cwd
        process.environment = environment()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data: Data = (try? pipe.fileHandleForReading.readToEnd() ?? Data()) ?? Data()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(
                domain: "GitFixtureHelper",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "git \(args.joined(separator: " ")) failed"]
            )
        }
        return data
    }

    /// Shell out inside the fixture — used for small ops like writing a file
    /// or invoking `git commit` from a test.
    static func exec(_ args: [String], cwd: URL) throws {
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
                domain: "GitFixtureHelper",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "git \(args.joined(separator: " ")) failed"]
            )
        }
    }
}
