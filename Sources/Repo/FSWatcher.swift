import CoreServices
import Foundation

/// FSEventStream-backed recursive filesystem watcher with user-level coalescing.
///
/// Design:
///
/// - The raw `FSEventStream` callback is scheduled on a dedicated dispatch
///   queue so it never blocks the main actor.
/// - On every raw callback we cancel the pending `DispatchWorkItem` and
///   enqueue a new one `coalesceMillis` out. When it finally fires it hops to
///   the MainActor and invokes `onChange`. This gives us a strict
///   "quiet period" semantic — a rapid burst of writes produces exactly one
///   user-facing callback (VAL-REPO-010, VAL-GRAPH-010).
/// - `stop()` is idempotent and safe from `deinit`. `FSEventStreamInvalidate`
///   + `FSEventStreamRelease` release the underlying stream so it doesn't
///   leak (common FSEvents bug — see `library/swiftui-macos.md` §6).
/// - macOS FSEvents itself can add up to ~500ms of latency before the
///   callback fires; callers should pick timeouts with that in mind.
///
/// Fulfills: VAL-REPO-010 (FSEvents refresh on external commit within 2s)
/// and partially VAL-GRAPH-010 (mechanism exists; M4-graph-scroll-container
/// wires scroll-position preservation).
final class FSWatcher: @unchecked Sendable {
    /// Thrown from `start()` when the watcher cannot be armed on the path.
    enum WatcherError: Error, LocalizedError {
        /// The path does not exist or is not a directory. FSEventStreamCreate
        /// itself does not fail on a missing path (it will happily accept
        /// one and simply never deliver events), so we pre-check.
        case invalidPath(path: String)
        /// `FSEventStreamCreate` returned nil — exhaustively rare given a
        /// valid directory, but surfaced anyway to satisfy the spec contract.
        case streamCreationFailed(path: String)

        var errorDescription: String? {
            switch self {
            case let .invalidPath(path):
                "FSWatcher: path does not exist or is not a directory: \(path)"
            case let .streamCreationFailed(path):
                "FSEventStreamCreate returned nil for path \(path)"
            }
        }
    }

    /// Dedicated queue. Serial so the raw callback and debounce scheduling
    /// never race against each other.
    private let queue = DispatchQueue(label: "nl.rb2.kite.fswatcher")

    private let path: URL
    private let coalesceMillis: UInt64
    private let onChange: @MainActor () -> Void

    // Mutated only while holding the state lock.
    private let stateLock = NSLock()
    private var stream: FSEventStreamRef?
    private var pendingWork: DispatchWorkItem?
    private var isStopped = false

    /// - Parameters:
    ///   - path: Directory to watch recursively. Must exist when `start()` runs.
    ///   - coalesceMillis: Quiet period (ms) after the last raw event before
    ///     `onChange` fires. Defaults to 500ms — matches mission.md §4 #9.
    ///   - onChange: Main-actor callback. Invoked on the MainActor after the
    ///     quiet period; never invoked off the main actor.
    init(
        path: URL,
        coalesceMillis: UInt64 = 500,
        onChange: @escaping @MainActor () -> Void
    ) {
        self.path = path
        self.coalesceMillis = coalesceMillis
        self.onChange = onChange
    }

    deinit {
        // `stop()` is safe from deinit: it only touches state protected by
        // its own lock, and FSEventStream APIs are fine to call from any
        // thread. No upward observer notifications.
        stop()
    }

    /// Start watching. Throws if `FSEventStreamCreate` returns nil — typical
    /// causes: the path doesn't exist, or the process can't observe it.
    func start() throws {
        stateLock.lock()
        defer { stateLock.unlock() }

        if stream != nil || isStopped {
            // Already started, or stopped and not restartable. Stopped
            // watchers intentionally do not restart — instantiate a fresh
            // FSWatcher instead.
            return
        }

        // FSEventStreamCreate accepts non-existent paths without error and
        // then never delivers events — surface the mistake eagerly so the
        // caller knows their watcher is not armed.
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else {
            throw WatcherError.invalidPath(path: path.path)
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let paths = [path.path] as CFArray
        let flags: FSEventStreamCreateFlags = UInt32(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        )

        // Latency value here is for FSEvents' own kernel-side coalescing; we
        // set it small (50ms) and do our authoritative coalescing via
        // DispatchWorkItem in `handleRawEvent`. This keeps the quiet-period
        // semantic predictable — otherwise two back-to-back writes could be
        // delivered as one event and our debounce would think the burst
        // ended earlier than it did.
        let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            FSWatcher.callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.05,
            flags
        )

        guard let created else {
            throw WatcherError.streamCreationFailed(path: path.path)
        }

        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        stream = created
    }

    /// Stop watching. Idempotent and safe to call from `deinit`, multiple
    /// times, or before `start()` has been invoked.
    func stop() {
        // Take the stream + pending work out under the lock, then perform
        // the actual release work outside the lock so we don't hold it
        // across a potentially-slow FSEventStreamInvalidate call.
        stateLock.lock()
        let taken = stream
        let pending = pendingWork
        stream = nil
        pendingWork = nil
        isStopped = true
        stateLock.unlock()

        if let pending {
            pending.cancel()
        }
        if let taken {
            FSEventStreamStop(taken)
            FSEventStreamInvalidate(taken)
            FSEventStreamRelease(taken)
        }
    }

    // MARK: - Internal

    /// Raw FSEvents callback. Called on `queue` because we set a dispatch
    /// queue via `FSEventStreamSetDispatchQueue`.
    private func handleRawEvent() {
        stateLock.lock()
        if isStopped {
            stateLock.unlock()
            return
        }
        // Cancel any previously-pending debounce to restart the quiet period.
        pendingWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Re-check stopped state at fire-time to avoid calling a
            // dropped-reference's onChange.
            stateLock.lock()
            let stopped = isStopped
            stateLock.unlock()
            if stopped { return }

            // Hop to the main actor. onChange is @MainActor so it is never
            // invoked off the main actor.
            Task { @MainActor in
                self.onChange()
            }
        }
        pendingWork = work
        stateLock.unlock()

        queue.asyncAfter(
            deadline: .now() + .milliseconds(Int(coalesceMillis)),
            execute: work
        )
    }

    /// Static C-compatible trampoline. `FSEventStreamCallback` cannot
    /// capture Swift context, so we pass `self` through the info pointer
    /// (see `FSEventStreamContext.info` above).
    private static let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
        guard let info else { return }
        let watcher = Unmanaged<FSWatcher>.fromOpaque(info).takeUnretainedValue()
        watcher.handleRawEvent()
    }
}
