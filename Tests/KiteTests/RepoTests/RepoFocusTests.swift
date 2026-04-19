import Foundation
import Testing
@testable import Kite

/// Tests for `RepoFocus`, the per-focused-repo state coordinator.
///
/// Uses real fixture repos (`GitFixtureHelper`) — FSEvents fires against
/// real files. Each test runs on the MainActor so `@MainActor` FSWatcher
/// callbacks can land without hopping.
///
/// Fulfills: VAL-NET-009, VAL-NET-010 (FSWatcher lifecycle portion).
@Suite("RepoFocus")
@MainActor
struct RepoFocusTests {
    /// FSEvents latency is ~500ms max, plus the watcher's 500ms coalesce.
    /// We pad to 2s for a stable pass on slower runners.
    private static let eventWaitSeconds: Double = 2.0

    @Test("creates a watcher for a work-tree repo and updates lastChangeAt on writes")
    func createsWatcherForWorkTree() async throws {
        let root = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { GitFixtureHelper.cleanup(root) }

        let repoURL = root.appendingPathComponent("alpha")
        try GitFixtureHelper.cleanRepo(at: repoURL)
        let discovered = DiscoveredRepo(
            url: repoURL,
            displayName: "alpha",
            rootPath: root,
            isBare: false
        )

        let focus = RepoFocus(repo: discovered)
        defer { focus.shutdown() }

        let initial = focus.lastChangeAt

        // Give FSEvents a moment to arm its subscription.
        try await Task.sleep(for: .milliseconds(200))

        // Write into .git/ — the watcher is armed on that dir.
        let marker = repoURL.appendingPathComponent(".git/kite-focus-marker.txt")
        try "change".write(to: marker, atomically: true, encoding: .utf8)

        try await Task.sleep(for: .seconds(Self.eventWaitSeconds))

        #expect(focus.lastChangeAt > initial, "Expected lastChangeAt to advance after .git/ write")
    }

    @Test("bare repo skips watcher and lastChangeAt remains at its initial value")
    func bareRepoSkipsWatcher() async throws {
        let parent = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { GitFixtureHelper.cleanup(parent) }

        let bare = parent.appendingPathComponent("server.git")
        try GitFixtureHelper.exec(["init", "--bare", bare.path], cwd: parent)

        let discovered = DiscoveredRepo(
            url: bare,
            displayName: "server.git",
            rootPath: parent,
            isBare: true
        )

        // Should instantiate cleanly with no watcher attached.
        let focus = RepoFocus(repo: discovered)
        defer { focus.shutdown() }

        let initial = focus.lastChangeAt

        // Write inside the bare git dir. No watcher means no update.
        try await Task.sleep(for: .milliseconds(200))
        try "noise".write(
            to: bare.appendingPathComponent("HEAD-sidecar.txt"),
            atomically: true,
            encoding: .utf8
        )
        try await Task.sleep(for: .seconds(Self.eventWaitSeconds))

        #expect(focus.lastChangeAt == initial, "Bare repo should not tick lastChangeAt")
    }

    @Test("shutdown releases the watcher and no further updates land")
    func shutdownReleasesWatcher() async throws {
        let root = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { GitFixtureHelper.cleanup(root) }

        let repoURL = root.appendingPathComponent("bravo")
        try GitFixtureHelper.cleanRepo(at: repoURL)
        let discovered = DiscoveredRepo(
            url: repoURL,
            displayName: "bravo",
            rootPath: root,
            isBare: false
        )

        let focus = RepoFocus(repo: discovered)

        // Arm, then shut down immediately.
        try await Task.sleep(for: .milliseconds(200))
        focus.shutdown()

        let afterShutdown = focus.lastChangeAt

        // Writes after shutdown should NOT update lastChangeAt.
        try "post-stop".write(
            to: repoURL.appendingPathComponent(".git/kite-post-stop.txt"),
            atomically: true,
            encoding: .utf8
        )
        try await Task.sleep(for: .seconds(Self.eventWaitSeconds))

        #expect(focus.lastChangeAt == afterShutdown, "Expected no further lastChangeAt updates after shutdown")
    }

    @Test("deinit shuts down cleanly; post-release writes produce no crash")
    func deinitShutsDown() async throws {
        let root = GitFixtureHelper.tempURL()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { GitFixtureHelper.cleanup(root) }

        let repoURL = root.appendingPathComponent("charlie")
        try GitFixtureHelper.cleanRepo(at: repoURL)
        let discovered = DiscoveredRepo(
            url: repoURL,
            displayName: "charlie",
            rootPath: root,
            isBare: false
        )

        // Scope so RepoFocus is released at scope end. If deinit misbehaves,
        // the crash lands right around here.
        do {
            let focus = RepoFocus(repo: discovered)
            _ = focus.lastChangeAt // silence unused
            try await Task.sleep(for: .milliseconds(200))
        }

        // Give ARC + FSEvents tear-down a moment.
        try await Task.sleep(for: .milliseconds(300))

        // Write into the dropped focus's old `.git/` — the callback must NOT
        // fire on a dead reference (proxy: if it did, ASan / a crashing
        // unretained self would surface here).
        try "after-release".write(
            to: repoURL.appendingPathComponent(".git/after-release.txt"),
            atomically: true,
            encoding: .utf8
        )
        try await Task.sleep(for: .seconds(Self.eventWaitSeconds))

        // Just reaching this line without a crash is the assertion.
        #expect(Bool(true))
    }
}
