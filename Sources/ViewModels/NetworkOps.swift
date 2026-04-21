import Foundation
import Observation
import OSLog

/// App-wide service that executes network-facing git ops against the
/// focused repo and routes their progress/outcome to `ProgressCenter` and
/// `ToastCenter`.
///
/// Scope for this iteration:
///   - `fetch(on:)` running `git fetch --all --prune --progress`.
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
///   - Branch-list refresh after a successful fetch is driven by
///     `FSWatcher`: `git fetch` writes under `.git/` which ticks
///     `RepoFocus.lastChangeAt`, which every per-repo `@Observable` view
///     model observes via `.onChange(of:)` (VAL-BRANCH-006).
///
/// Fulfills: VAL-NET-001, VAL-NET-005, VAL-NET-011, VAL-BRANCH-006.
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

    /// Run `git fetch --all --prune --progress` on the focused repo. Returns
    /// `true` on a clean exit (after enqueuing a success toast), `false`
    /// otherwise (after enqueuing a classified error toast). A cancelled Task
    /// returns `false` without raising a toast — cancellation is normal (focus
    /// swap, window close) and doesn't deserve a red banner.
    @discardableResult
    func fetch(on focus: RepoFocus) async -> Bool {
        let repoDisplayName = focus.repo.displayName
        let progressId = progress.begin(label: "Fetch \(repoDisplayName)")
        let parser = ProgressParser()
        // Box so the @Sendable `focus.queue.run` closure can mutate across
        // its async stream iteration without tripping Sendable capture rules.
        let stderrAccumulator = StderrAccumulator()
        let repoURL = focus.repo.url

        do {
            try await focus.queue.run { @Sendable in
                let stream = Git.stream(
                    args: ["fetch", "--all", "--prune", "--progress"],
                    cwd: repoURL
                )
                for try await event in stream {
                    switch event {
                    case .stdoutLine:
                        // `git fetch` is mostly silent on stdout; skip without
                        // capturing so we don't pad the error detail blob.
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
            toasts.success("Fetched \(repoDisplayName)")
            return true
        } catch is CancellationError {
            progress.end(progressId)
            return false
        } catch {
            progress.end(progressId)
            let stderrBlob = await stderrAccumulator.joined()
            let classified = classify(error: error, stderr: stderrBlob)
            let message = (classified as? LocalizedError)?.errorDescription ?? "Fetch failed"
            toasts.error(message, detail: stderrBlob.isEmpty ? nil : stderrBlob)
            Self.logger.error("""
            NetworkOps.fetch failed for \(repoDisplayName, privacy: .public): \
            \(message, privacy: .public)
            """)
            return false
        }
    }

    // MARK: - Private

    /// Prefer the already-typed `GitError` thrown above when the raw stderr
    /// doesn't classify (e.g. the stream ended without matching any pattern).
    /// Otherwise prefer the classified version so the toast reads nicely.
    private func classify(error: Error, stderr: String) -> Error {
        if let typed = ErrorClassifier.classify(stderr: stderr, exitCode: 1) {
            return typed
        }
        return error
    }
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
