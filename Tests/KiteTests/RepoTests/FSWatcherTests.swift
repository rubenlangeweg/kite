import Foundation
import Testing
@testable import Kite

/// Tests for `FSWatcher`, the FSEventStream-backed directory watcher.
///
/// FSEvents has significant native latency (up to ~500ms before our callback
/// fires) plus our 500ms user-level coalesce window. Tests sleep 2s after a
/// write / burst to be robust; callbacks that _should not_ fire are sampled
/// after 1s.
@Suite("FSWatcher")
struct FSWatcherTests {
    /// A single synchronous write inside the watched directory produces
    /// exactly one `onChange` within the coalesce window.
    @Test("fires onChange after a file is created in the watched directory")
    func watcherFiresOnFileCreation() async throws {
        let tmp = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { GitFixtureHelper.cleanup(tmp) }

        let counter = CallbackCounter()
        let watcher = FSWatcher(path: tmp, coalesceMillis: 250) {
            counter.bump()
        }
        try watcher.start()
        defer { watcher.stop() }

        // Let FSEvents arm its subscription before the first write.
        try await Task.sleep(for: .milliseconds(150))

        try "hello".write(
            to: tmp.appendingPathComponent("a.txt"),
            atomically: true,
            encoding: .utf8
        )

        // FSEvents latency (~500ms max) + coalesce (250ms) + padding.
        try await Task.sleep(for: .seconds(2))

        #expect(counter.value >= 1, "Expected onChange to fire at least once; got \(counter.value)")
    }

    /// 10 rapid writes inside the coalesce window should produce exactly one
    /// `onChange` — not one per write.
    @Test("coalesces rapid bursts into a single callback")
    func watcherCoalescesRapidBursts() async throws {
        let tmp = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { GitFixtureHelper.cleanup(tmp) }

        let counter = CallbackCounter()
        let watcher = FSWatcher(path: tmp, coalesceMillis: 500) {
            counter.bump()
        }
        try watcher.start()
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(150))

        // 10 writes back-to-back. Stay under the coalesce window of 500ms
        // so every event must debounce into a single callback.
        for idx in 0 ..< 10 {
            try "burst \(idx)".write(
                to: tmp.appendingPathComponent("burst-\(idx).txt"),
                atomically: true,
                encoding: .utf8
            )
        }

        // Wait comfortably past FSEvents latency + our 500ms coalesce to
        // confirm no late duplicate fires.
        try await Task.sleep(for: .seconds(2))

        #expect(counter.value == 1, "Expected exactly 1 coalesced callback; got \(counter.value)")
    }

    /// After `stop()`, no further callbacks should fire for new writes.
    @Test("stop prevents any further callbacks")
    func stopPreventsFurtherCallbacks() async throws {
        let tmp = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { GitFixtureHelper.cleanup(tmp) }

        let counter = CallbackCounter()
        let watcher = FSWatcher(path: tmp, coalesceMillis: 200) {
            counter.bump()
        }
        try watcher.start()

        try await Task.sleep(for: .milliseconds(150))
        watcher.stop()

        try "after-stop".write(
            to: tmp.appendingPathComponent("after.txt"),
            atomically: true,
            encoding: .utf8
        )

        // Anything that was going to fire would do so well within 1s.
        try await Task.sleep(for: .seconds(1))

        #expect(counter.value == 0, "stop() must prevent callbacks; got \(counter.value)")
    }

    /// `start()` against a non-existent path must surface an error — no
    /// silent swallow, no stream created.
    @Test("throws when started on a non-existent path")
    func invalidPathThrows() throws {
        let missing = URL(fileURLWithPath: "/nonexistent/kite-test-\(UUID().uuidString)")

        let counter = CallbackCounter()
        let watcher = FSWatcher(path: missing) {
            counter.bump()
        }

        #expect(throws: FSWatcher.WatcherError.self) {
            try watcher.start()
        }
    }

    /// Dropping all references to a watcher must release its FSEventStream
    /// cleanly (no crash) and leave the path re-watchable by a fresh
    /// instance. Hard to prove "no leak" in a unit test — minimally we
    /// confirm no crash and that a second watcher still sees events.
    @Test("deinit releases the stream safely and a fresh watcher works")
    func deinitReleasesStream() async throws {
        let tmp = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { GitFixtureHelper.cleanup(tmp) }

        // Scope 1: watcher instantiated, started, then released via scope exit.
        do {
            let firstCounter = CallbackCounter()
            let first = FSWatcher(path: tmp, coalesceMillis: 200) {
                firstCounter.bump()
            }
            try first.start()
            try await Task.sleep(for: .milliseconds(150))
        }
        // Give ARC + FSEvents tear-down a moment; a broken deinit tends to
        // crash around here.
        try await Task.sleep(for: .milliseconds(300))

        // Scope 2: fresh watcher on the same path. A correctly-released
        // prior stream leaves us free to observe new writes.
        let secondCounter = CallbackCounter()
        let second = FSWatcher(path: tmp, coalesceMillis: 200) {
            secondCounter.bump()
        }
        try second.start()
        defer { second.stop() }
        try await Task.sleep(for: .milliseconds(150))

        try "second".write(
            to: tmp.appendingPathComponent("second.txt"),
            atomically: true,
            encoding: .utf8
        )

        try await Task.sleep(for: .seconds(2))

        #expect(secondCounter.value >= 1, "Fresh watcher should observe events; got \(secondCounter.value)")
    }
}

/// Thread-safe counter used by the watcher's `@MainActor` callback and read
/// back by the test body. The callback hops to the main actor before
/// bumping, so accesses are coherent, but a lock keeps the counter safe if
/// the test bodies are ever dispatched off-main.
final class CallbackCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count: Int = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func bump() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}
