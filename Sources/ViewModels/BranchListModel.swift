import Foundation
import Observation
import OSLog

/// View model for the middle column's branch list (VAL-BRANCH-001/002/003/004).
///
/// Runs `git branch --list` / `git branch -r --list` / `git symbolic-ref`
/// against the focused repo via `focus.queue.run { ... }` so the per-repo
/// serialization contract from `GitQueue` is preserved. Results are parsed
/// with `BranchParser` and partitioned into `local`, remote-by-remote
/// groupings, and an optional `DetachedHead` pseudo-row.
///
/// On any error the model clears its visible state and exposes a
/// user-readable message via `lastError`; the failure is also logged via
/// `os.Logger` so it remains observable in Console.app (per AGENTS.md's
/// "never silently swallow errors" rule).
@Observable
@MainActor
final class BranchListModel {
    private(set) var local: [Branch] = []
    private(set) var remote: [String: [Branch]] = [:]
    private(set) var detachedHead: DetachedHead?
    private(set) var isLoading: Bool = false
    private(set) var lastError: String?

    /// Timestamp of the most recent `RepoFocus.lastChangeAt` value we reloaded
    /// for. `BranchListView` observes `focus.lastChangeAt` and triggers a
    /// reload on every change; this guards against repeated reloads for the
    /// same tick (which SwiftUI can hand us across view refreshes).
    @ObservationIgnored
    private var lastFSTick: Date?

    @ObservationIgnored
    private static let logger = Logger(subsystem: "nl.rb2.kite", category: "git")

    /// Branch listing format string — 6 NUL-separated fields, one record per
    /// line. Matches `BranchParser`'s expected input shape.
    @ObservationIgnored
    static let branchFormat =
        "%(refname:short)%00%(refname)%00%(objectname)%00%(upstream:short)%00%(upstream:track)%00%(HEAD)"

    init() {}

    /// Reload branch state for the given `RepoFocus`. Serialises git calls via
    /// the focus's `GitQueue` so concurrent UI reloads + net ops don't tread
    /// on each other's `.git/index.lock`.
    func reload(for focus: RepoFocus) async {
        lastFSTick = focus.lastChangeAt
        isLoading = true
        defer { isLoading = false }

        do {
            let localParsed = try await fetchBranches(args: ["branch", "--list"], focus: focus)
            let remoteParsed = try await fetchBranches(args: ["branch", "-r", "--list"], focus: focus)
            let detached = try await probeDetachedHead(focus: focus)

            local = localParsed
            remote = groupByRemote(remoteParsed)
            detachedHead = detached
            lastError = nil
        } catch is CancellationError {
            // Cancellation is normal (e.g. focus swap). Don't touch visible
            // state — the new focus's reload will repopulate it.
            return
        } catch {
            Self.logger.error("""
            BranchListModel.reload failed for \(focus.repo.url.path, privacy: .public): \
            \(error.localizedDescription, privacy: .public)
            """)
            local = []
            remote = [:]
            detachedHead = nil
            lastError = error.localizedDescription
        }
    }

    /// Run `git branch [-r|--list] --format=…` and parse the output.
    private func fetchBranches(args: [String], focus: RepoFocus) async throws -> [Branch] {
        let fullArgs = args + ["--format=\(Self.branchFormat)"]
        let repoURL = focus.repo.url
        let result = try await focus.queue.run {
            try await Git.run(args: fullArgs, cwd: repoURL)
        }
        try result.throwIfFailed()
        return try BranchParser.parse(result.stdout)
    }

    /// Probe for detached HEAD. `symbolic-ref -q --short HEAD` exits 1 when
    /// HEAD is detached; in that case we capture the short SHA. An empty repo
    /// (no commits) has neither a symbolic ref nor a reachable HEAD, so we
    /// gate the SHA capture on `rev-parse --verify HEAD` succeeding.
    private func probeDetachedHead(focus: RepoFocus) async throws -> DetachedHead? {
        let repoURL = focus.repo.url
        let symbolic = try await focus.queue.run {
            try await Git.run(args: ["symbolic-ref", "-q", "--short", "HEAD"], cwd: repoURL)
        }
        guard symbolic.exitCode != 0 else { return nil }

        let verify = try await focus.queue.run {
            try await Git.run(args: ["rev-parse", "--verify", "--quiet", "HEAD"], cwd: repoURL)
        }
        guard verify.exitCode == 0 else { return nil }

        let short = try await focus.queue.run {
            try await Git.run(args: ["rev-parse", "--short", "HEAD"], cwd: repoURL)
        }
        guard short.exitCode == 0 else { return nil }
        let sha = short.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sha.isEmpty else { return nil }
        return DetachedHead(shortSHA: sha)
    }

    /// Stable-sorted remote names (used by the view for deterministic rendering).
    var remoteNames: [String] {
        remote.keys.sorted()
    }

    // MARK: - Private

    private func groupByRemote(_ branches: [Branch]) -> [String: [Branch]] {
        var grouped: [String: [Branch]] = [:]
        for branch in branches {
            guard branch.isRemote, let remoteName = branch.remote else { continue }
            // Filter remote HEAD pointers. Git emits `refs/remotes/<remote>/HEAD`
            // for every remote that has had `set-head` run (common for
            // `origin`). We match on the `fullName` because `refname:short`
            // strips the trailing `/HEAD`, leaving just the remote name —
            // a `hasSuffix("/HEAD")` on `shortName` misses these entries.
            if branch.fullName.hasSuffix("/HEAD") { continue }
            grouped[remoteName, default: []].append(branch)
        }
        // Sort each remote's branches by shortName for a stable UI order.
        for (key, value) in grouped {
            grouped[key] = value.sorted { $0.shortName < $1.shortName }
        }
        return grouped
    }
}

/// Snapshot of a detached HEAD (commit without a symbolic ref).
struct DetachedHead: Equatable {
    let shortSHA: String
}
