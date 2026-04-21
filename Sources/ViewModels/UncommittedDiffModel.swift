import Foundation
import Observation
import OSLog

/// View model backing `UncommittedDiffView` — the read-only unified-diff pane
/// for the working copy (VAL-DIFF-001/002/004/005).
///
/// Fetches both halves of the working-copy diff concurrently inside a single
/// `focus.queue.run { ... }` block, preserving the per-repo `GitQueue`
/// contract while halving round-trip latency vs a chain of awaits:
///
///   - `git diff --no-color --patch -U3`          — unstaged (worktree vs index)
///   - `git diff --no-color --patch -U3 --staged` — staged   (index vs HEAD)
///
/// Output size for these commands can legitimately exceed the pipe-buffer
/// ceiling (~64 KB) on large uncommitted diffs; the M1-fix-git-run-drain fix
/// to `Git.run` — concurrent pipe drain via `readabilityHandler` — is the
/// prerequisite that makes this safe. Without that fix a large diff would
/// deadlock the child on a full pipe.
///
/// Cancel-prior-Task discipline (per INTERFACES.md §4 fan-out rule): every
/// call to `reload(for:)` cancels the previous in-flight reload before
/// starting a new one. A superseded reload throws `CancellationError`, is
/// silently absorbed here, and does NOT clobber `unstaged`/`staged` with
/// partial state.
@Observable
@MainActor
final class UncommittedDiffModel {
    private(set) var unstaged: [FileDiff] = []
    private(set) var staged: [FileDiff] = []
    private(set) var isLoading: Bool = false
    private(set) var lastError: String?

    @ObservationIgnored
    private static let logger = Logger(subsystem: "nl.rb2.kite", category: "diff")

    /// Handle to the in-flight reload so a follow-up reload can cancel the
    /// previous one. Never touched off the main actor.
    @ObservationIgnored
    private var loadTask: Task<Void, Never>?

    init() {}

    /// Reload both diffs for the given focus. Cancels any prior in-flight
    /// reload first, then serialises through `focus.queue.run` so we respect
    /// the per-repo `GitQueue` contract alongside other operations touching
    /// the same repo (graph reload, status reload, fetch/pull/push).
    ///
    /// The returned `async` call completes once this reload has either
    /// succeeded, surfaced an error, or been superseded by a later reload.
    func reload(for focus: RepoFocus) async {
        loadTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await performReload(for: focus)
        }
        loadTask = task
        await task.value
    }

    /// Clear every piece of observable state. Used when the focused repo
    /// unmounts so the UI doesn't keep stale rows for an unfocused repo.
    func clear() {
        loadTask?.cancel()
        loadTask = nil
        unstaged = []
        staged = []
        isLoading = false
        lastError = nil
    }

    // MARK: - Internals

    private func performReload(for focus: RepoFocus) async {
        isLoading = true
        defer { isLoading = false }

        let repoURL = focus.repo.url
        do {
            let (unstagedDiff, stagedDiff) = try await focus.queue.run {
                try await Self.fetchDiffs(repoURL: repoURL)
            }

            try Task.checkCancellation()

            unstaged = unstagedDiff
            staged = stagedDiff
            lastError = nil
        } catch is CancellationError {
            // Cancellation is normal (focus swap, follow-up reload). Don't
            // clobber state — the successor reload (or `clear()`) repopulates.
            return
        } catch {
            Self.logger.error("""
            UncommittedDiffModel.reload failed for \(repoURL.path, privacy: .public): \
            \(error.localizedDescription, privacy: .public)
            """)
            unstaged = []
            staged = []
            lastError = error.localizedDescription
        }
    }

    /// Fan out the two `git diff` reads concurrently. The caller wraps this in
    /// a single `focus.queue.run { ... }` so the queue boundary stays outer
    /// while the subprocess fan-out stays inner — same pattern as GraphModel.
    private static func fetchDiffs(repoURL: URL) async throws -> ([FileDiff], [FileDiff]) {
        async let unstagedOutput = Git.run(
            args: ["diff", "--no-color", "--patch", "-U3"],
            cwd: repoURL
        )
        async let stagedOutput = Git.run(
            args: ["diff", "--no-color", "--patch", "-U3", "--staged"],
            cwd: repoURL
        )

        let unstagedResult = try await unstagedOutput
        let stagedResult = try await stagedOutput

        try unstagedResult.throwIfFailed()
        try stagedResult.throwIfFailed()

        let unstagedParsed = try DiffParser.parse(unstagedResult.stdout)
        let stagedParsed = try DiffParser.parse(stagedResult.stdout)
        return (unstagedParsed, stagedParsed)
    }
}
