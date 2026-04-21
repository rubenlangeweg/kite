import Foundation
import Observation
import OSLog

/// Per-focused-repo state coordinator.
///
/// Owns the lifecycle of everything that's scoped to "the user's currently
/// focused repo": the `FSWatcher` on `.git/`, the `GitQueue` that serializes
/// git ops against the repo, and a timestamp (`lastChangeAt`) that bumps on
/// every filesystem change so views observing the focus auto-refresh.
///
/// `FSWatcher` is one-shot — `RepoStore` creates a fresh `RepoFocus` on every
/// repo switch so we always pair a new watcher with the newly focused repo.
/// Previous `RepoFocus` instances are released via ARC; their `deinit` calls
/// `shutdown()` which tears the watcher + cancels any in-flight task.
///
/// Bare repos have no `.git/` subdirectory (they *are* the git dir), so
/// `RepoFocus` skips watcher setup for them — they still work, just without
/// auto-refresh. Same fallback applies if `FSWatcher.start()` throws: we log
/// and keep going so the repo remains usable via ⌘R.
///
/// Fulfills: VAL-NET-009/010 alongside `GitQueue` + `RepoStore`.
@Observable
@MainActor
final class RepoFocus {
    @ObservationIgnored
    private static let logger = Logger(subsystem: "nl.rb2.kite", category: "repo")

    /// The repo this focus is scoped to. Immutable for the focus's lifetime.
    let repo: DiscoveredRepo

    /// Per-repo op serializer. Callers use `focus.queue.run { ... }` for any
    /// git-touching work to guarantee serial execution on this repo's
    /// `.git/` directory.
    let queue: GitQueue

    /// Timestamp of the most recent FSEvents fire (or focus creation, if
    /// none has fired yet). Views observing the focused repo re-query git
    /// whenever this changes.
    private(set) var lastChangeAt: Date = .init()

    @ObservationIgnored
    private var watcher: FSWatcher?

    @ObservationIgnored
    private var rootTask: Task<Void, Never>?

    @ObservationIgnored
    private var isShutDown: Bool = false

    init(repo: DiscoveredRepo) {
        self.repo = repo
        queue = GitQueue(repoURL: repo.url)
        watcher = nil

        // Watcher setup is deferred past the stored-property init so the
        // callback can legally capture `self`. Bare repos skip this phase.
        guard !repo.isBare else { return }
        let gitDir = repo.url.appendingPathComponent(".git")
        let built = FSWatcher(path: gitDir) { [weak self] in
            guard let self, !isShutDown else { return }
            lastChangeAt = .init()
        }
        do {
            try built.start()
            watcher = built
        } catch {
            // Log and proceed — the repo is still usable, just without
            // auto-refresh. Matches the AGENTS.md "never silently swallow"
            // rule: we log rather than catch-and-forget.
            Self.logger.error("""
            RepoFocus: FSWatcher failed to start for \(repo.url.path, privacy: .public): \
            \(error.localizedDescription, privacy: .public)
            """)
        }
    }

    deinit {
        // `shutdown()`-equivalent inlined here — deinit can run on any
        // thread, so we touch only fields that are safe off-main. Cancel
        // the sidecar task (safe from any thread) and stop the FSWatcher
        // (its `stop()` is documented to be callable from any thread,
        // including deinit).
        rootTask?.cancel()
        watcher?.stop()
    }

    /// Idempotent teardown. Cancels the sidecar task (if any) and stops the
    /// FSWatcher. Called explicitly by `RepoStore` on focus swap so teardown
    /// runs on the main actor; the deinit fallback exists for callers that
    /// drop the reference without swapping.
    func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        rootTask?.cancel()
        rootTask = nil
        watcher?.stop()
        watcher = nil
    }

    /// Programmatically re-fire the FSEvents-style "something changed" tick
    /// so every observer of `focus.lastChangeAt` reloads. Used by the ⌘R
    /// menu action (M8-commands-and-menu) — same effect as an external
    /// `git commit` firing FSEvents, minus the disk activity.
    func forceRefresh() {
        lastChangeAt = .init()
    }
}
