import Foundation
import Observation
import OSLog

/// View model backing `StatusHeaderView` — the compact working-tree summary
/// shown above the branch list (VAL-BRANCH-005).
///
/// Runs `git status --porcelain=v2 --branch -z` through `focus.queue` so the
/// per-repo serialization contract from `GitQueue` is preserved. Output is
/// parsed by `StatusParser` into a `StatusSummary`; any failure clears the
/// visible summary and exposes a user-readable `lastError` (failures are also
/// logged via `os.Logger` per AGENTS.md's "never silently swallow" rule).
///
/// `StatusHeaderView` observes `focus.lastChangeAt` and reloads on every
/// FSWatcher tick — that wiring closes the end-to-end loop for VAL-REPO-010
/// (external `git commit` → FSEvents → header refresh).
@Observable
@MainActor
final class StatusHeaderModel {
    private(set) var summary: StatusSummary?
    private(set) var isLoading: Bool = false
    private(set) var lastError: String?

    /// Timestamp of the most recent `RepoFocus.lastChangeAt` we reloaded for.
    /// Kept so the view's `onChange(of:)` reload can be idempotent across
    /// SwiftUI's redundant fires.
    @ObservationIgnored
    private(set) var lastFSTick: Date?

    @ObservationIgnored
    private static let logger = Logger(subsystem: "nl.rb2.kite", category: "git")

    init() {}

    /// Reload the status summary for the given `RepoFocus`. Cancellation
    /// (focus swap, task replacement) is silently tolerated; the new reload
    /// will repopulate state.
    func reload(for focus: RepoFocus) async {
        lastFSTick = focus.lastChangeAt
        isLoading = true
        defer { isLoading = false }

        let repoURL = focus.repo.url
        do {
            let result = try await focus.queue.run {
                try await Git.run(
                    args: ["status", "--porcelain=v2", "--branch", "-z"],
                    cwd: repoURL
                )
            }
            try result.throwIfFailed()
            summary = try StatusParser.parse(result.stdout)
            lastError = nil
        } catch is CancellationError {
            return
        } catch {
            Self.logger.error("""
            StatusHeaderModel.reload failed for \(repoURL.path, privacy: .public): \
            \(error.localizedDescription, privacy: .public)
            """)
            summary = nil
            lastError = error.localizedDescription
        }
    }
}
