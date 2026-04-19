import Foundation
import Testing
@testable import Kite

@Suite("Git.run / Git.stream")
struct GitRunTests {
    @Test("Git.run returns exit 0 for git --version")
    func runReturnsZeroExitForVersionCommand() async throws {
        let tmp = FileManager.default.temporaryDirectory
        let result = try await Git.run(args: ["--version"], cwd: tmp)
        #expect(result.exitCode == 0)
        #expect(result.isSuccess)
        #expect(result.stdout.contains("git version"))
    }

    @Test("Git.buildEnvironment sets the three required keys")
    func runSetsRequiredEnvironment() {
        let env = Git.buildEnvironment(extra: [:])
        #expect(env["GIT_TERMINAL_PROMPT"] == "0")
        #expect(env["GIT_OPTIONAL_LOCKS"] == "0")
        #expect(env["LC_ALL"] == "C")
    }

    @Test("Git uses absolute /usr/bin/git path")
    func runUsesAbsolutePath() {
        #expect(Git.executablePath == URL(fileURLWithPath: "/usr/bin/git"))
    }

    @Test("Git.run surfaces non-zero exit in GitResult without throwing")
    func runPropagatesNonZeroExit() async throws {
        let tmp = FileManager.default.temporaryDirectory
        let result = try await Git.run(args: ["definitely-not-a-real-subcommand"], cwd: tmp)
        #expect(result.exitCode != 0)
        #expect(!result.isSuccess)
    }

    @Test("Pre-cancelled Task throws .cancelled before launching a Process")
    func runThrowsOnPreCancelledTask() async throws {
        let repo = GitFixtureHelper.tempURL()
        defer { GitFixtureHelper.cleanup(repo) }
        try GitFixtureHelper.cleanRepo(at: repo)

        let task = Task { () throws -> GitResult in
            // Cancel synchronously so the in-Task checkCancellation call fires
            // before we touch Process.
            try Task.checkCancellation()
            return try await Git.run(args: ["status", "--porcelain"], cwd: repo)
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected pre-cancelled task to throw")
        } catch is CancellationError {
            // Expected — structured concurrency surfaces cancellation.
        } catch let error as GitError {
            // Git.run itself calls try Task.checkCancellation() first and throws.
            if case .cancelled = error { return }
            Issue.record("Unexpected GitError: \(error)")
        }
    }

    @Test("Cancelling mid-flight terminates the child Process within 5s")
    func runCancelsMidFlightProcess() async throws {
        // Deterministic long-running git invocation: route SSH transport
        // through a shell script that unconditionally sleeps. git invokes
        // `ssh <host> <remote-cmd>` for ssh:// URLs, so the script gets extra
        // positional args — it ignores them and just sleeps. git blocks
        // reading the script's (never-arriving) pack-protocol response.
        let repo = GitFixtureHelper.tempURL()
        defer { GitFixtureHelper.cleanup(repo) }
        try GitFixtureHelper.cleanRepo(at: repo)

        let scriptURL = GitFixtureHelper.tempURL().appendingPathExtension("sh")
        try "#!/bin/sh\nsleep 30\n".write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { GitFixtureHelper.cleanup(scriptURL) }
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: scriptURL.path
        )

        let started = Date()
        let task = Task { () throws -> GitResult in
            try await Git.run(
                args: [
                    "-c", "core.sshCommand=\(scriptURL.path)",
                    "ls-remote",
                    "ssh://git@localhost/kite-test-unreachable.git"
                ],
                cwd: repo
            )
        }

        // Give git ~300ms to fork the fake-ssh script and enter its sleep.
        try await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()

        var threw = false
        do {
            let result = try await task.value
            Issue.record("Expected cancellation, got result with exit=\(result.exitCode)")
        } catch let error as GitError {
            threw = true
            switch error {
            case .cancelled, .processFailed, .networkUnreachable, .auth:
                break // All indicate the child is no longer running.
            default:
                Issue.record("Unexpected GitError on cancellation: \(error)")
            }
        } catch is CancellationError {
            threw = true
        }
        let elapsed = Date().timeIntervalSince(started)
        #expect(threw, "Cancellation should produce a thrown error (elapsed=\(elapsed)s)")
        #expect(elapsed < 5.0, "Cancellation too slow: \(elapsed)s — child wasn't terminated")
    }

    @Test("Git.run preserves cwd for repo-scoped commands")
    func runHonorsWorkingDirectory() async throws {
        let repo = GitFixtureHelper.tempURL()
        defer { GitFixtureHelper.cleanup(repo) }
        try GitFixtureHelper.cleanRepo(at: repo)

        let result = try await Git.run(args: ["rev-parse", "--show-toplevel"], cwd: repo)
        #expect(result.isSuccess)
        // On macOS, temp paths may be symlinked through /private/var; both
        // canonical forms are acceptable.
        let reported = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(reported.hasSuffix(repo.lastPathComponent))
    }

    @Test("Git.stream yields stdout lines and a .completed event with exit code")
    func streamYieldsLinesAndCompletion() async throws {
        let tmp = FileManager.default.temporaryDirectory
        var stdoutLines: [String] = []
        var completionExit: Int32?

        let stream = Git.stream(args: ["--version"], cwd: tmp)
        for try await event in stream {
            switch event {
            case let .stdoutLine(line):
                stdoutLines.append(line)
            case .stderrLine:
                continue
            case let .completed(code):
                completionExit = code
            }
        }

        #expect(completionExit == 0)
        #expect(stdoutLines.contains(where: { $0.contains("git version") }))
    }

    @Test("Git.ensureAvailable succeeds on this host")
    func testEnsureAvailable() throws {
        try Git.ensureAvailable()
    }

    @Test("parseVersion extracts major.minor")
    func testParseVersion() {
        let apple = Git.parseVersion("git version 2.50.1 (Apple Git-155)")
        #expect(apple?.major == 2)
        #expect(apple?.minor == 50)

        let plain = Git.parseVersion("git version 2.40.0")
        #expect(plain?.major == 2)
        #expect(plain?.minor == 40)

        #expect(Git.parseVersion("total garbage") == nil)
    }
}
