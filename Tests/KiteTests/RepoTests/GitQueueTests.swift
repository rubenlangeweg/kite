import Foundation
import Testing
@testable import Kite

/// Tests for `GitQueue`, the per-repo op serializer.
///
/// Fulfills: VAL-NET-009 (per-repo GitQueue serializes ops),
/// partially VAL-NET-010 (cancellation propagation).
@Suite("GitQueue")
struct GitQueueTests {
    /// Three `run` calls enqueued in order must complete in the same order.
    /// An actor serializes messages that don't suspend internally: a `body`
    /// that does synchronous work runs to completion before the actor
    /// accepts the next `run(_:)` message.
    ///
    /// Note on concurrency semantics: if a body `await`s a suspension point
    /// (e.g. `Task.sleep`) the actor is momentarily free to pick up the
    /// next message — exactly how actor reentrancy is spec'd. For the M3
    /// use-case (`queue.run { try await Git.run(...) }`), the serialization
    /// that matters is at the `.git/index.lock` level: the subprocess
    /// holds that lock for its full lifetime and `Git.run` doesn't return
    /// until termination, so one subprocess finishes before the next
    /// enters git territory even if the actor itself is free in between.
    /// This test verifies the stronger guarantee — mail-ordered, non-
    /// overlapping body execution — using synchronous bodies, which is
    /// the tight contract callers can rely on when their body does only
    /// CPU-bound work.
    @Test("serializes concurrent ops in enqueue order")
    func serializesConcurrentOps() async throws {
        let queue = GitQueue(repoURL: URL(fileURLWithPath: "/tmp/kite-gitqueue"))
        let recorder = CompletionRecorder()
        let started = AsyncSignal()
        let release = AsyncSignal()

        // Op 1 holds the actor until `release` fires — so ops 2 and 3 can
        // queue behind it deterministically.
        let first = Task {
            try await queue.run {
                await started.signal()
                await release.wait()
                await recorder.append(1)
            }
        }

        await started.wait()

        // Ops 2 and 3 use synchronous bodies. Once op 1 completes, the
        // actor processes its mailbox in FIFO order and each body runs to
        // completion before the next starts.
        let second = Task {
            try await queue.run {
                await recorder.append(2)
            }
        }
        // Small sleep to ensure op 2's send-to-actor has landed in the
        // mailbox before op 3's. Swift actors preserve FIFO on arrivals;
        // simultaneous arrivals are broken by the runtime's scheduling.
        try await Task.sleep(for: .milliseconds(50))
        let third = Task {
            try await queue.run {
                await recorder.append(3)
            }
        }
        try await Task.sleep(for: .milliseconds(50))

        await release.signal()

        _ = try await (first.value, second.value, third.value)

        let order = await recorder.order
        #expect(order == [1, 2, 3], "Expected mail-order completion [1,2,3]; got \(order)")
    }

    /// Cancelling the outer Task during an in-flight op should propagate
    /// through `run` via structured concurrency.
    @Test("cancellation propagates into the queued op")
    func cancellationPropagates() async throws {
        let queue = GitQueue(repoURL: URL(fileURLWithPath: "/tmp/kite-gitqueue"))
        let started = AsyncSignal()

        let task = Task {
            try await queue.run {
                await started.signal()
                // Long sleep we expect to be cancelled.
                try await Task.sleep(for: .seconds(30))
            }
        }

        // Wait for the body to actually start before cancelling; otherwise
        // we'd be testing "queue declines already-cancelled work" which is
        // a different behavior.
        await started.wait()
        task.cancel()

        do {
            try await task.value
            Issue.record("Expected cancellation to throw; got clean completion")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError; got \(error)")
        }
    }

    /// Exceptions thrown inside the body rethrow out of `run` unchanged.
    @Test("exceptions bubble out unchanged")
    func exceptionsBubbleOut() async {
        let queue = GitQueue(repoURL: URL(fileURLWithPath: "/tmp/kite-gitqueue"))

        do {
            _ = try await queue.run {
                throw FakeError.boom
            } as Void
            Issue.record("Expected throw; got clean completion")
        } catch let error as FakeError {
            #expect(error == .boom)
        } catch {
            Issue.record("Expected FakeError.boom; got \(error)")
        }
    }

    // MARK: - Test support

    private enum FakeError: Error, Equatable {
        case boom
    }

    /// Collects integers in the order `append` was called. Actor so concurrent
    /// queue callers can record without racing.
    private actor CompletionRecorder {
        private(set) var order: [Int] = []

        func append(_ value: Int) {
            order.append(value)
        }
    }

    /// One-shot async signal — `signal()` wakes a pending `wait()`.
    /// Simpler than pulling in `AsyncStream` plumbing for a single hand-off.
    private actor AsyncSignal {
        private var fired: Bool = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func signal() {
            fired = true
            let pending = waiters
            waiters.removeAll()
            for cont in pending {
                cont.resume()
            }
        }

        func wait() async {
            if fired { return }
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                waiters.append(cont)
            }
        }
    }
}
