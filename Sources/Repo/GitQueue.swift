import Foundation

/// Per-repo operation serializer. Any two calls to `run(_:)` for the same
/// `GitQueue` instance execute sequentially — a second caller's `body` does
/// not start until the first caller's `body` has finished, even when the
/// body awaits long-running async work (e.g. `Git.run` on a child process).
/// This keeps `.git/index.lock` sane across concurrent ops on the same repo.
///
/// One instance per focused repo. Owned by `RepoFocus`; dropped when the
/// focus changes so per-queue state naturally resets.
///
/// Implementation detail: Swift actors serialize *message entry* in FIFO
/// order but are re-entrant across `await` suspension points — meaning the
/// trivial `try await body()` would let a second `run` begin executing
/// while the first's body is still awaiting its subprocess. We explicitly
/// chain ops via a "latest completion" continuation. Each `run` installs
/// a new completion gate, awaits the previous one, runs its body, then
/// fires its own gate for the next caller.
///
/// Cancellation propagates through structured concurrency: cancelling the
/// caller's Task surfaces as a `CancellationError` either during the wait
/// on the prior gate or inside `body` (including `Git.run`, which
/// terminates its child `Process`). A cancellation event does NOT break
/// the chain — the gate is always fulfilled so subsequent ops proceed.
///
/// Fulfills: VAL-NET-009 (per-repo GitQueue serializes ops),
/// partially VAL-NET-010 (cancellation propagation through the queue).
actor GitQueue {
    /// Absolute URL of the repo this queue serializes operations for. Held
    /// so callers and logs can identify per-queue activity without threading
    /// an extra parameter through every `run(_:)` call. `nonisolated` so
    /// synchronous access (logging, equality checks) doesn't have to cross
    /// the actor boundary for an immutable value.
    nonisolated let repoURL: URL

    /// Awaited by the next op, fulfilled when the current op finishes.
    /// nil when the queue is idle (first caller installs its gate and
    /// skips the wait).
    private var latestGate: CompletionGate?

    init(repoURL: URL) {
        self.repoURL = repoURL
    }

    /// Run a closure under the queue's serialization. Throws and cancellation
    /// bubble out unchanged. Execution order matches `run(_:)` call order
    /// (FIFO mailbox — actor entry is already FIFO; we add cross-suspension
    /// serialization on top via a completion gate chain).
    func run<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        let priorGate = latestGate
        let myGate = CompletionGate()
        latestGate = myGate

        // Wait for the previous op to finish. Actor reentrancy means this
        // await releases the actor — allowing later `run` callers to land
        // here and install their own gate behind ours. FIFO is preserved
        // because each gate strictly awaits its immediate predecessor.
        await priorGate?.wait()

        defer { myGate.fire() }
        return try await body()
    }
}

/// One-shot gate used to chain ops inside `GitQueue`. A single waiter awaits
/// a single fire. Reference type so the actor's stored value and the
/// caller's local reference observe the same state.
private final class CompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var fired: Bool = false
    private var waiter: CheckedContinuation<Void, Never>?

    func fire() {
        lock.lock()
        fired = true
        let waiter = waiter
        self.waiter = nil
        lock.unlock()
        waiter?.resume()
    }

    func wait() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            if fired {
                lock.unlock()
                cont.resume()
                return
            }
            waiter = cont
            lock.unlock()
        }
    }
}
