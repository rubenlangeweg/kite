import Foundation
import Observation
import OSLog

/// Background auto-fetch timer scoped to the focused repo.
///
/// Fires `NetworkOps.fetch(on:)` every `intervalSeconds` (default 300s) on
/// whichever `RepoFocus` is currently active, and cancels itself on:
///   - focus change (new repo selected) — `retarget(to:)` swaps the task.
///   - window close / view onDisappear — `stop()` hard-cancels.
///   - Settings "Enable auto-fetch" toggled off — RootView's `.onChange`
///     calls `retarget(to:)` which consults `persistence.settings.autoFetchEnabled`
///     and decides not to re-arm.
///
/// The timer runs *relative to the `retarget` call* — it sleeps the full
/// interval first, then fires a fetch. The user just selected the repo; they
/// don't want an immediate fetch barrage. Manual ⌘⇧F is always available for
/// right-now semantics.
///
/// Serialisation with manual fetch/pull/push is handled by `focus.queue` inside
/// `NetworkOps.fetch(on:)` — the queue's `CompletionGate` chain guarantees
/// that an auto-fetch firing concurrently with a user-triggered op runs
/// sequentially on the same `.git/` directory (VAL-NET-009).
///
/// Fulfills: VAL-NET-006, VAL-NET-007.
@Observable
@MainActor
final class AutoFetchController {
    @ObservationIgnored
    private let ops: NetworkOps

    @ObservationIgnored
    private let persistence: PersistenceStore

    @ObservationIgnored
    private var task: Task<Void, Never>?

    @ObservationIgnored
    private var currentFocusID: DiscoveredRepo.ID?

    @ObservationIgnored
    private static let logger = Logger(subsystem: "nl.rb2.kite", category: "git")

    /// Interval between auto-fetches, in seconds. Default 300s (5 minutes).
    /// Exposed so tests can shorten the wait without redefining the loop.
    @ObservationIgnored
    var intervalSeconds: UInt64 = 300

    /// Test-only introspection: is a timer task currently scheduled?
    var isRunning: Bool {
        task != nil
    }

    init(ops: NetworkOps, persistence: PersistenceStore) {
        self.ops = ops
        self.persistence = persistence
    }

    /// Start (or restart) a repeating auto-fetch for `focus`, or stop if
    /// `focus` is nil. Called from RootView on focus change and on Settings
    /// toggle change.
    ///
    /// Contract:
    ///   - Any prior task is cancelled before a new one is spawned.
    ///   - If `focus` is nil, no task is spawned.
    ///   - If `persistence.settings.autoFetchEnabled` is false, no task is
    ///     spawned. Re-enabling the toggle plus a subsequent retarget call
    ///     picks it up.
    ///   - The loop sleeps first, then fetches — callers never see an
    ///     immediate fetch from this method.
    func retarget(to focus: RepoFocus?) {
        task?.cancel()
        task = nil
        currentFocusID = focus?.repo.id

        guard let focus else { return }
        guard persistence.settings.autoFetchEnabled else { return }

        let interval = intervalSeconds
        task = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: interval * 1_000_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                guard let self else { return }
                // Re-check the toggle each tick so an off-flip during the
                // wait window silently skips the fetch rather than firing
                // one last time.
                guard persistence.settings.autoFetchEnabled else { continue }
                // Focus-change guard: if the user switched repos during the
                // sleep, the stored `currentFocusID` will no longer match
                // this task's captured focus. Stop rather than fetching on
                // a stale repo.
                guard focus.repo.id == currentFocusID else { return }
                _ = await ops.fetch(on: focus)
            }
        }
    }

    /// Hard-stop. Cancels the timer task and forgets the current focus.
    /// Called from RootView's `.onDisappear` (window close).
    func stop() {
        task?.cancel()
        task = nil
        currentFocusID = nil
    }
}
