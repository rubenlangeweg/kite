import Foundation

/// Low-level wrapper around `/usr/bin/git` subprocess invocations.
///
/// All `Process` launches use the absolute path `/usr/bin/git` (no `PATH`
/// lookup — fulfills VAL-SEC-004). Every invocation sets:
///
///   - `GIT_TERMINAL_PROMPT=0` — fails fast instead of prompting for creds
///     (VAL-NET-008, VAL-SEC-005).
///   - `GIT_OPTIONAL_LOCKS=0` — read-only commands don't contend with the
///     user's terminal git for `index.lock` (VAL-SEC-005).
///   - `LC_ALL=C` (and `LANG=C`) — stable parseable English output.
///
/// Task cancellation is propagated to the child via `process.terminate()`
/// (VAL-NET-010).
///
/// Domain models (`Commit`, `Branch`, etc.) live under `Sources/Git/Models/`
/// and are introduced by `M1-git-parsers`.
enum Git {
    /// Absolute path to the system git binary. Never resolved via PATH.
    static let executablePath: URL = .init(fileURLWithPath: "/usr/bin/git")

    /// Minimum supported git version (major, minor).
    static let minimumVersion: (major: Int, minor: Int) = (2, 40)

    /// Run `/usr/bin/git` with the given args and cwd, returning captured
    /// stdout/stderr/exit. Non-zero exit is NOT thrown — the caller decides
    /// via `GitResult.throwIfFailed(classifier:)` or by inspecting `exitCode`.
    ///
    /// Both stdout and stderr are drained CONCURRENTLY with the child via
    /// `FileHandle.readabilityHandler` callbacks writing into lock-guarded
    /// byte buffers. A post-termination `readToEnd()` flushes any tail bytes
    /// that remained in the pipe after EOF. This avoids the ~64 KB pipe-buffer
    /// deadlock that afflicted the earlier post-termination-only variant —
    /// large outputs (`git diff`, `git show`, `git log --patch`, `git archive`)
    /// would stall the child indefinitely when either pipe filled.
    static func run(
        args: [String],
        cwd: URL,
        env extraEnv: [String: String] = [:]
    ) async throws -> GitResult {
        let process = makeProcess(args: args, cwd: cwd, extraEnv: extraEnv)

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading

        let stdoutAccum = ByteAccumulator()
        let stderrAccum = ByteAccumulator()

        // Track cancellation separately from Task.isCancelled so the terminationHandler
        // (running on a random DispatchQueue) can see it.
        let cancelFlag = CancelFlag()

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<GitResult, Error>) in
                attachDrainingHandlers(
                    stdoutHandle: outHandle,
                    stderrHandle: errHandle,
                    stdoutAccum: stdoutAccum,
                    stderrAccum: stderrAccum
                )
                process.terminationHandler = { proc in
                    let (stdout, stderr) = finalizeAccumulators(
                        stdoutHandle: outHandle,
                        stderrHandle: errHandle,
                        stdoutAccum: stdoutAccum,
                        stderrAccum: stderrAccum
                    )
                    if cancelFlag.isSet {
                        // SIGTERM from our cancellation handler. Surface as .cancelled
                        // rather than a generic non-zero exit so callers can distinguish.
                        cont.resume(throwing: GitError.cancelled)
                        return
                    }
                    cont.resume(returning: GitResult(
                        exitCode: proc.terminationStatus,
                        stdout: stdout,
                        stderr: stderr
                    ))
                }
                do {
                    try process.run()
                } catch {
                    outHandle.readabilityHandler = nil
                    errHandle.readabilityHandler = nil
                    cont.resume(throwing: GitError.missingExecutable(
                        "Failed to launch /usr/bin/git: \(error.localizedDescription)"
                    ))
                }
            }
        } onCancel: {
            cancelFlag.set()
            if process.isRunning {
                process.terminate()
            }
        }
    }

    /// Wire `readabilityHandler` on each pipe to drain bytes into the matching
    /// accumulator while the child runs. Handlers self-detach on EOF.
    private static func attachDrainingHandlers(
        stdoutHandle: FileHandle,
        stderrHandle: FileHandle,
        stdoutAccum: ByteAccumulator,
        stderrAccum: ByteAccumulator
    ) {
        stdoutHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                stdoutAccum.append(data)
            }
        }
        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                stderrAccum.append(data)
            }
        }
    }

    /// Called from `terminationHandler`. Detaches the readability handlers,
    /// flushes any residual bytes (anything sitting in the kernel pipe buffer
    /// after the child's final write but before EOF propagated through the
    /// dispatch source), and returns the UTF-8 decoded strings.
    private static func finalizeAccumulators(
        stdoutHandle: FileHandle,
        stderrHandle: FileHandle,
        stdoutAccum: ByteAccumulator,
        stderrAccum: ByteAccumulator
    ) -> (stdout: String, stderr: String) {
        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil
        if let tail = try? stdoutHandle.readToEnd(), !tail.isEmpty {
            stdoutAccum.append(tail)
        }
        if let tail = try? stderrHandle.readToEnd(), !tail.isEmpty {
            stderrAccum.append(tail)
        }
        return (stdoutAccum.utf8String(), stderrAccum.utf8String())
    }

    /// Stream git stdout/stderr line-by-line. Terminal event is `.completed`.
    ///
    /// Only yields raw lines — progress parsing (mapping
    /// `Receiving objects: N%\r` → percent) is owned by
    /// `ProgressParser` in `M1-git-parsers`.
    static func stream(
        args: [String],
        cwd: URL,
        env extraEnv: [String: String] = [:]
    ) -> AsyncThrowingStream<GitEvent, Error> {
        AsyncThrowingStream { continuation in
            let process = makeProcess(args: args, cwd: cwd, extraEnv: extraEnv)

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            process.standardInput = FileHandle.nullDevice

            let outReader = LineReader { line in
                continuation.yield(.stdoutLine(line))
            }
            let errReader = LineReader { line in
                continuation.yield(.stderrLine(line))
            }

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { return }
                outReader.feed(data)
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { return }
                errReader.feed(data)
            }

            process.terminationHandler = { proc in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                outReader.flush()
                errReader.flush()
                continuation.yield(.completed(exitCode: proc.terminationStatus))
                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                if process.isRunning {
                    process.terminate()
                }
            }

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: GitError.missingExecutable(
                    "Failed to launch /usr/bin/git: \(error.localizedDescription)"
                ))
            }
        }
    }

    /// Called once at app startup. Throws if git is missing or too old.
    static func ensureAvailable() throws {
        let fm = FileManager.default
        let path = executablePath.path
        guard fm.isExecutableFile(atPath: path) else {
            throw GitError.missingExecutable(
                "Expected /usr/bin/git to be an executable file; install Xcode Command Line Tools."
            )
        }
        // Synchronous version probe; cheap (<20ms) and only runs once.
        let process = Process()
        process.executableURL = executablePath
        process.arguments = ["--version"]
        process.environment = buildEnvironment(extra: [:])
        process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw GitError.missingExecutable("Cannot launch /usr/bin/git: \(error.localizedDescription)")
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitError.missingExecutable("git --version exited with \(process.terminationStatus)")
        }
        let data: Data = (try? pipe.fileHandleForReading.readToEnd() ?? Data()) ?? Data()
        let output = String(bytes: data, encoding: .utf8) ?? ""
        guard let parsed = parseVersion(output) else {
            throw GitError.missingExecutable("Unrecognized git --version output: \(output)")
        }
        let (major, minor) = minimumVersion
        if parsed.major < major || (parsed.major == major && parsed.minor < minor) {
            throw GitError.missingExecutable(
                "git \(parsed.major).\(parsed.minor) is older than required \(major).\(minor)."
            )
        }
    }

    // MARK: - Internal helpers (exposed for @testable tests)

    /// Build the environment dict applied to every git `Process`. Parent env
    /// is inherited (so `SSH_AUTH_SOCK`, credential helpers, etc. Just Work)
    /// then the required keys are overlaid.
    static func buildEnvironment(extra: [String: String]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        env["LC_ALL"] = "C"
        env["LANG"] = "C"
        env["GIT_PAGER"] = "cat"
        for (key, value) in extra {
            env[key] = value
        }
        return env
    }

    static func parseVersion(_ output: String) -> (major: Int, minor: Int)? {
        // Expected: "git version 2.50.1 (Apple Git-155)\n" or similar.
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: #"(\d+)\.(\d+)"#, options: .regularExpression) else {
            return nil
        }
        let parts = trimmed[range].split(separator: ".")
        guard parts.count >= 2, let maj = Int(parts[0]), let min = Int(parts[1]) else {
            return nil
        }
        return (maj, min)
    }

    private static func makeProcess(
        args: [String],
        cwd: URL,
        extraEnv: [String: String]
    ) -> Process {
        let process = Process()
        process.executableURL = executablePath
        process.arguments = args
        process.currentDirectoryURL = cwd
        process.environment = buildEnvironment(extra: extraEnv)
        return process
    }
}

/// Thread-safe byte accumulator for `Git.run` pipe draining. Lock-guarded
/// rather than actor-based so it can be appended to synchronously from
/// `FileHandle.readabilityHandler` (which runs on an internal dispatch
/// source) AND from the `terminationHandler` (which runs on an arbitrary
/// DispatchQueue) without hopping through an async Task. Using a Task-based
/// actor would have risked the continuation resuming before the last append
/// landed.
private final class ByteAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) {
        lock.lock()
        buffer.append(data)
        lock.unlock()
    }

    func utf8String() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: buffer, encoding: .utf8) ?? ""
    }
}

/// Thread-safe flag used to communicate Task cancellation from the cancellation
/// handler into the process's `terminationHandler`, which runs on an arbitrary
/// DispatchQueue and cannot observe `Task.isCancelled` directly.
private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }

    func set() {
        lock.lock()
        defer { lock.unlock() }
        flag = true
    }
}

/// Reads byte chunks, emits full `\n`-terminated lines. Also splits on `\r`
/// so fetch/push progress (`Receiving objects:  42%\r`) surfaces as distinct
/// lines — `ProgressParser` (M1-git-parsers) is responsible for mapping them.
private final class LineReader: @unchecked Sendable {
    private var buffer = Data()
    private let onLine: (String) -> Void

    init(onLine: @escaping (String) -> Void) {
        self.onLine = onLine
    }

    func feed(_ data: Data) {
        buffer.append(data)
        emitLines()
    }

    func flush() {
        if !buffer.isEmpty {
            if let trailing = String(data: buffer, encoding: .utf8), !trailing.isEmpty {
                onLine(trailing)
            }
            buffer.removeAll(keepingCapacity: false)
        }
    }

    private func emitLines() {
        while let idx = buffer.firstIndex(where: { $0 == 0x0a || $0 == 0x0d }) {
            let lineData = buffer.subdata(in: buffer.startIndex ..< idx)
            buffer.removeSubrange(buffer.startIndex ... idx)
            if let line = String(data: lineData, encoding: .utf8) {
                onLine(line)
            }
        }
    }
}
