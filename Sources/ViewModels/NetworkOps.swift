import Foundation
import Observation
import OSLog

/// App-wide service that executes network-facing git ops against the
/// focused repo and routes their progress/outcome to `ProgressCenter` and
/// `ToastCenter`.
///
/// Scope:
///   - `fetch(on:)` → `git fetch --all --prune --progress`
///   - `pullFFOnly(on:)` → `git pull --ff-only --progress`
///   - `push(on:currentBranch:)` → `git push --progress` (no force)
///   - `pushWithUpstream(on:branch:remote:)` → `git push --set-upstream <remote> <branch> --progress`
///
/// Design:
///   - Each op is serialised against the focused repo via `focus.queue.run`
///     so two rapid triggers execute sequentially on the same `.git/`
///     directory (VAL-NET-009).
///   - Progress is streamed line-by-line out of `Git.stream`; stderr lines
///     flow through `ProgressParser` → `ProgressCenter.update(id:percent:)`
///     for the toolbar indicator (VAL-NET-011, VAL-UI-006).
///   - On success we enqueue a green auto-dismissing toast (VAL-NET-005).
///   - On failure we classify stderr via `ErrorClassifier`, surface a red
///     sticky toast with the full stderr available via click-to-expand
///     (VAL-UI-005), and log through `os.Logger`.
///
/// Force-push flags (the two-dash "force" and "force-with-lease" forms) are
/// intentionally absent from every argument list here.
/// `SecurityInvariantsTests` grep-proves this invariant across the entire
/// source tree (VAL-SEC-001).
///
/// Fulfills: VAL-NET-001, VAL-NET-002, VAL-NET-003, VAL-NET-004,
/// VAL-NET-005, VAL-NET-011, VAL-SEC-001, VAL-BRANCH-006.
@Observable
@MainActor
final class NetworkOps {
    @ObservationIgnored
    private let toasts: ToastCenter

    @ObservationIgnored
    private let progress: ProgressCenter

    @ObservationIgnored
    private static let logger = Logger(subsystem: "nl.rb2.kite", category: "git")

    init(toasts: ToastCenter, progress: ProgressCenter) {
        self.toasts = toasts
        self.progress = progress
    }

    // MARK: - Public API

    /// Run `git fetch --all --prune --progress` on the focused repo. Returns
    /// `true` on a clean exit (after enqueuing a success toast), `false`
    /// otherwise (after enqueuing a classified error toast). A cancelled Task
    /// returns `false` without raising a toast — cancellation is normal (focus
    /// swap, window close) and doesn't deserve a red banner.
    @discardableResult
    func fetch(on focus: RepoFocus) async -> Bool {
        let repoDisplayName = focus.repo.displayName
        let outcome = await runStreaming(
            on: focus,
            args: ["fetch", "--all", "--prune", "--progress"],
            progressLabel: "Fetch \(repoDisplayName)"
        )
        switch outcome {
        case .success:
            toasts.success("Fetched \(repoDisplayName)")
            return true
        case .cancelled:
            return false
        case let .failed(error: _, stderr: stderrBlob, classified: classified):
            presentFailure(
                error: classified,
                stderr: stderrBlob,
                fallback: "Fetch failed",
                logContext: "NetworkOps.fetch failed for \(repoDisplayName)"
            )
            return false
        }
    }

    /// Run `git pull --ff-only --progress` on the focused repo. Returns `true`
    /// on success, `false` otherwise. Non-fast-forward and other classified
    /// errors produce sticky error toasts with actionable messages
    /// (VAL-NET-002).
    @discardableResult
    func pullFFOnly(on focus: RepoFocus) async -> Bool {
        let repoDisplayName = focus.repo.displayName
        let outcome = await runStreaming(
            on: focus,
            args: ["pull", "--ff-only", "--progress"],
            progressLabel: "Pull \(repoDisplayName)"
        )
        switch outcome {
        case .success:
            toasts.success("Pulled \(repoDisplayName)")
            return true
        case .cancelled:
            return false
        case let .failed(error: _, stderr: stderrBlob, classified: classified):
            let message = pullErrorMessage(for: classified)
            toasts.error(message, detail: stderrBlob.isEmpty ? nil : stderrBlob)
            Self.logger.error("""
            NetworkOps.pullFFOnly failed for \(repoDisplayName, privacy: .public): \
            \(message, privacy: .public)
            """)
            return false
        }
    }

    /// Run `git push --progress` on the focused repo. Returns a `PushOutcome`
    /// describing one of three terminal states:
    ///   - `.success` — push completed.
    ///   - `.needsUpstream(...)` — the current branch has no upstream; the
    ///     UI should offer a confirmation sheet to set one.
    ///   - `.failed` — any other failure; a sticky error toast is already
    ///     on screen.
    ///
    /// Never passes the two-dash "force" or "force-with-lease" push flags.
    /// Fulfills VAL-NET-003 and (together with `SecurityInvariantsTests`)
    /// VAL-SEC-001.
    func push(on focus: RepoFocus, currentBranch: String?) async -> PushOutcome {
        let repoDisplayName = focus.repo.displayName
        let outcome = await runStreaming(
            on: focus,
            args: ["push", "--progress"],
            progressLabel: "Push \(repoDisplayName)"
        )
        switch outcome {
        case .success:
            toasts.success("Pushed \(repoDisplayName)")
            return .success
        case .cancelled:
            return .failed
        case let .failed(error: _, stderr: stderrBlob, classified: classified):
            // .noUpstream is special: don't toast — let the caller show the
            // upstream-set confirmation sheet. Everything else surfaces a
            // sticky error toast with a message tuned to the specific cause.
            if let gitError = classified as? GitError, case .noUpstream = gitError {
                let branch = currentBranch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !branch.isEmpty else {
                    // We know the remote is missing but can't determine the
                    // branch name — fall through to a generic error toast.
                    presentFailure(
                        error: classified,
                        stderr: stderrBlob,
                        fallback: "Push failed",
                        logContext: "NetworkOps.push failed for \(repoDisplayName)"
                    )
                    return .failed
                }
                return .needsUpstream(branch: branch, remote: "origin")
            }
            let message = pushErrorMessage(for: classified)
            toasts.error(message, detail: stderrBlob.isEmpty ? nil : stderrBlob)
            Self.logger.error("""
            NetworkOps.push failed for \(repoDisplayName, privacy: .public): \
            \(message, privacy: .public)
            """)
            return .failed
        }
    }

    /// Run `git push --set-upstream <remote> <branch> --progress` on the
    /// focused repo. Used by the UI after the user confirms the "set
    /// upstream?" sheet surfaced by `push(on:currentBranch:)`. Returns `true`
    /// on success, `false` otherwise.
    @discardableResult
    func pushWithUpstream(on focus: RepoFocus, branch: String, remote: String) async -> Bool {
        let repoDisplayName = focus.repo.displayName
        let outcome = await runStreaming(
            on: focus,
            args: ["push", "--set-upstream", remote, branch, "--progress"],
            progressLabel: "Push \(repoDisplayName)"
        )
        switch outcome {
        case .success:
            toasts.success("Pushed \(branch) to \(remote)")
            return true
        case .cancelled:
            return false
        case let .failed(error: _, stderr: stderrBlob, classified: classified):
            let message = pushErrorMessage(for: classified)
            toasts.error(message, detail: stderrBlob.isEmpty ? nil : stderrBlob)
            Self.logger.error("""
            NetworkOps.pushWithUpstream failed for \(repoDisplayName, privacy: .public): \
            \(message, privacy: .public)
            """)
            return false
        }
    }

    // MARK: - Private streaming helper

    /// Shared implementation for every streaming network op: begin a
    /// progress item, stream the process, feed stderr into `ProgressParser`,
    /// end the progress item, and return a structured outcome the caller
    /// maps to a toast.
    private func runStreaming(
        on focus: RepoFocus,
        args: [String],
        progressLabel: String
    ) async -> StreamOutcome {
        let progressId = progress.begin(label: progressLabel)
        let parser = ProgressParser()
        let stderrAccumulator = StderrAccumulator()
        let repoURL = focus.repo.url

        do {
            try await focus.queue.run { @Sendable in
                let stream = Git.stream(args: args, cwd: repoURL)
                for try await event in stream {
                    switch event {
                    case .stdoutLine:
                        continue
                    case let .stderrLine(line):
                        await stderrAccumulator.append(line)
                        let feed = line + "\n"
                        if let event = parser.consume(feed), let pct = event.percent {
                            await MainActor.run {
                                self.progress.update(progressId, percent: pct)
                            }
                        }
                    case let .completed(exitCode):
                        if exitCode != 0 {
                            let stderr = await stderrAccumulator.joined()
                            throw GitError.processFailed(exitCode: exitCode, stderr: stderr)
                        }
                    }
                }
            }
            progress.end(progressId)
            return .success
        } catch is CancellationError {
            progress.end(progressId)
            return .cancelled
        } catch {
            progress.end(progressId)
            let stderrBlob = await stderrAccumulator.joined()
            let classified = classify(error: error, stderr: stderrBlob)
            return .failed(error: error, stderr: stderrBlob, classified: classified)
        }
    }

    /// Route a classified failure to a generic error toast + log line.
    private func presentFailure(
        error: Error,
        stderr: String,
        fallback: String,
        logContext: String
    ) {
        let message = (error as? LocalizedError)?.errorDescription ?? fallback
        toasts.error(message, detail: stderr.isEmpty ? nil : stderr)
        Self.logger.error("\(logContext, privacy: .public): \(message, privacy: .public)")
    }

    // MARK: - Error classification

    /// Prefer the already-typed `GitError` thrown above when the raw stderr
    /// doesn't classify. Otherwise prefer the classified version so the toast
    /// reads nicely.
    private func classify(error: Error, stderr: String) -> Error {
        if let typed = ErrorClassifier.classify(stderr: stderr, exitCode: 1) {
            return typed
        }
        return error
    }

    /// Map a classified pull error to the VAL-NET-002 user-facing message.
    private func pullErrorMessage(for error: Error) -> String {
        if let gitError = error as? GitError {
            switch gitError {
            case .nonFastForward:
                return "Non-fast-forward: pull requires fast-forward. Rebase or merge in terminal."
            case let .auth(detail):
                return "Authentication failed. Check ssh-agent or credential helper. \(detail)"
            case let .remoteRejected(detail):
                return "Remote rejected the pull: \(detail)."
            case let .protectedBranch(detail):
                return "Branch is protected on the remote: \(detail)."
            case let .hookRejected(detail):
                return "A pre-receive or update hook rejected the update: \(detail)"
            case let .noUpstream(detail):
                return "No upstream branch configured. \(detail)"
            default:
                break
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? "Pull failed"
    }

    /// Map a classified push error to the VAL-NET-003 / VAL-NET-004 user-facing
    /// message. `.noUpstream` is intentionally excluded here — callers route
    /// that case to the upstream-set sheet instead.
    private func pushErrorMessage(for error: Error) -> String {
        if let gitError = error as? GitError {
            switch gitError {
            case .auth:
                return "Authentication failed. Check ssh-agent or credential helper."
            case .nonFastForward:
                return "Non-fast-forward: pull or rebase before pushing."
            case let .protectedBranch(detail):
                return "Branch is protected on the remote: \(detail)."
            case let .hookRejected(reason):
                return "A pre-receive or update hook rejected the push: \(reason)"
            case let .remoteRejected(reason):
                return "Remote rejected the push: \(reason)"
            default:
                break
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? "Push failed"
    }
}

/// Outcome of `NetworkOps.push(on:currentBranch:)`. Callers map this to either
/// a sticky toast (handled internally) or an upstream-set confirmation sheet.
enum PushOutcome: Equatable {
    case success
    case needsUpstream(branch: String, remote: String)
    case failed
}

/// Internal outcome of one streaming op. Converted to the public shape by the
/// caller (e.g. `fetch` returns `Bool`, `push` returns `PushOutcome`).
private enum StreamOutcome {
    case success
    case cancelled
    case failed(error: Error, stderr: String, classified: Error)
}

/// Small actor holding the stderr tail from a streaming git op. The
/// `focus.queue.run` closure must be `@Sendable` so we can't close over a
/// plain `var [String]`; an actor is the smallest safe container.
private actor StderrAccumulator {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func joined() -> String {
        lines.joined(separator: "\n")
    }
}
