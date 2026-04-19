import Foundation
import Observation
import OSLog

/// View model backing `GraphView` — loads the commit graph for the focused
/// repo (VAL-GRAPH-009/010/011).
///
/// Runs four git commands concurrently (log / refs / HEAD / shallow) inside a
/// single `focus.queue.run { ... }` block per `git-engine-worker` / AGENTS.md
/// subprocess discipline: the queue boundary is outer, fan-out is inner. This
/// halves the round-trip latency versus a chain of awaits while preserving the
/// per-repo serialization contract against concurrent net ops.
///
/// Design notes:
///
///   - `selectedSHA` is the routing channel to the (future, M7) diff pane —
///     `GraphView` binds to `select(sha:)` on row tap. When M7 lands, its
///     detail view observes this property to drive `git show <sha>`.
///   - 200 is the commit cap across the mission. When the log returns exactly
///     200 records we flip `commitLimitHit` so the footer appears; fewer
///     records means the repo's full history fits.
///   - Shallow detection uses `rev-parse --is-shallow-repository`; prints
///     `true\n` or `false\n` on stdout.
///   - `clear()` resets all observable state — called when the focused repo
///     unmounts so the UI doesn't keep stale rows for an unfocused repo.
///   - A live reload Task is tracked so a second reload kicks off cancellation
///     of the prior in-flight one (cheap; `Git.run` propagates cancellation to
///     `Process.terminate()`). This complies with AGENTS.md's per-focus
///     observer fan-out rule: only one reload in flight per GraphModel.
///
/// Fulfills: VAL-GRAPH-009 (selection routing), VAL-GRAPH-010 (state that
/// backs scroll preservation via stable `id`), VAL-GRAPH-011 (shallow flag).
@Observable
@MainActor
final class GraphModel {
    /// The layout rows rendered in the List, in topo order (newest first).
    private(set) var rows: [LayoutRow] = []

    /// True while a reload is in flight. Used by the view to decorate the
    /// initial load; subsequent reloads keep showing the previous rows so the
    /// List's stable-id scroll preservation works (VAL-GRAPH-010).
    private(set) var isLoading: Bool = false

    /// True when `git rev-parse --is-shallow-repository` returned "true".
    private(set) var isShallowRepo: Bool = false

    /// True when the log cap (200) was hit — there are older commits not
    /// visible. The view renders a footer row to surface that (VAL-GRAPH-001
    /// truncation marker).
    private(set) var commitLimitHit: Bool = false

    /// Localized error message from the last failed reload; nil on success.
    private(set) var lastError: String?

    /// SHA of the commit the user tapped. Future M7 diff pane observes this.
    private(set) var selectedSHA: String?

    /// Commit cap for the `git log` query — mirrors the mission-wide v1 scope
    /// ("last 200 commits"). Exposed `internal` so tests can compare counts.
    static let commitCap = 200

    @ObservationIgnored
    private static let logger = Logger(subsystem: "nl.rb2.kite", category: "graph")

    /// Handle to the in-flight reload Task so a subsequent reload can cancel
    /// the previous one. Never touched off the main actor.
    @ObservationIgnored
    private var activeReload: Task<Void, Never>?

    init() {}

    /// Reload the graph for `focus`. Cancels any prior in-flight reload first,
    /// then serializes through `focus.queue.run` so we respect the per-repo
    /// `GitQueue` contract alongside other operations touching the same repo.
    func reload(for focus: RepoFocus) async {
        activeReload?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await performReload(for: focus)
        }
        activeReload = task
        await task.value
    }

    /// Clear every piece of observable state. Used when the focused repo
    /// unmounts (store.focus set to nil).
    func clear() {
        activeReload?.cancel()
        activeReload = nil
        rows = []
        isLoading = false
        isShallowRepo = false
        commitLimitHit = false
        lastError = nil
        selectedSHA = nil
    }

    /// Record the user's commit selection. The view binds this to row-tap and
    /// future M7 diff pane observes the published value to fetch `git show`.
    func select(sha: String?) {
        selectedSHA = sha
    }

    // MARK: - Internals

    /// Execute the four-concurrent-call reload inside the focus queue.
    private func performReload(for focus: RepoFocus) async {
        isLoading = true
        defer { isLoading = false }

        let repoURL = focus.repo.url
        do {
            let output = try await focus.queue.run {
                try await Self.fetchGraphInputs(repoURL: repoURL)
            }

            try Task.checkCancellation()

            let commits = try LogParser.parse(output.log)
            let refsMap = try ForEachRefParser.parse(output.refs)
            let currentBranch = Self.parseCurrentBranch(output.currentBranchOutput)
            let shallow = Self.parseShallow(output.shallowOutput)

            let laid = GraphLayout.compute(commits)
            let enriched = GraphRowRefs.enrich(laid, refsBySHA: refsMap, currentBranch: currentBranch)

            rows = enriched
            isShallowRepo = shallow
            commitLimitHit = commits.count >= Self.commitCap
            lastError = nil
        } catch is CancellationError {
            // Cancellation is normal (focus swap, follow-up reload). Don't
            // clobber state — the successor reload (or `clear()`) repopulates.
            return
        } catch {
            Self.logger.error("""
            GraphModel.reload failed for \(repoURL.path, privacy: .public): \
            \(error.localizedDescription, privacy: .public)
            """)
            rows = []
            isShallowRepo = false
            commitLimitHit = false
            lastError = error.localizedDescription
        }
    }

    /// Plain-struct container for the four git outputs — keeps the four
    /// `async let`s returning one value the caller can unpack.
    private struct GraphInputs {
        let log: String
        let refs: String
        let currentBranchOutput: GitResult
        let shallowOutput: GitResult
    }

    /// Fan out the four reads concurrently. The caller wraps this in a single
    /// `focus.queue.run { ... }` so the queue boundary stays outer while the
    /// subprocess fan-out stays inner (per git-engine-worker SKILL.md).
    private static func fetchGraphInputs(repoURL: URL) async throws -> GraphInputs {
        async let logResult = Git.run(
            args: [
                "log",
                "--all",
                "--topo-order",
                "--format=%H%x00%P%x00%an%x00%ae%x00%at%x00%s",
                "-n", "\(commitCap)",
                "-z"
            ],
            cwd: repoURL
        )
        async let refsResult = Git.run(
            args: [
                "for-each-ref",
                "--format=%(objectname) %(refname)%00%(*objectname)"
            ],
            cwd: repoURL
        )
        async let currentBranchResult = Git.run(
            args: ["symbolic-ref", "--short", "-q", "HEAD"],
            cwd: repoURL
        )
        async let shallowResult = Git.run(
            args: ["rev-parse", "--is-shallow-repository"],
            cwd: repoURL
        )

        let log = try await logResult
        let refs = try await refsResult
        let head = try await currentBranchResult
        let shallow = try await shallowResult

        // Log and refs MUST succeed — they carry the visible content. An
        // empty repo (no commits yet) legitimately exits 128 on `git log`
        // with "does not have any commits yet"; surface as empty rows, not
        // an error.
        if !log.isSuccess {
            if Self.stderrIndicatesEmptyRepo(log.stderr) {
                return GraphInputs(
                    log: "",
                    refs: refs.isSuccess ? refs.stdout : "",
                    currentBranchOutput: head,
                    shallowOutput: shallow
                )
            }
            try log.throwIfFailed()
        }
        try refs.throwIfFailed()
        // `symbolic-ref` legitimately exits 1 on detached HEAD; `rev-parse
        // --is-shallow-repository` always exits 0 in a real repo. Neither is
        // raised here — the parsers below tolerate non-zero exits.

        return GraphInputs(
            log: log.stdout,
            refs: refs.stdout,
            currentBranchOutput: head,
            shallowOutput: shallow
        )
    }

    /// `git log` exits 128 in a fresh `git init` with no commits yet, with
    /// stderr like `fatal: your current branch 'main' does not have any
    /// commits yet`. That's not an error the user cares about — show an empty
    /// graph.
    private static func stderrIndicatesEmptyRepo(_ stderr: String) -> Bool {
        let lowered = stderr.lowercased()
        return lowered.contains("does not have any commits yet")
            || lowered.contains("bad default revision 'head'")
    }

    /// `symbolic-ref --short HEAD` exits 1 on detached HEAD; otherwise
    /// prints the short branch name on stdout. Return nil for either failure
    /// mode so downstream enrichment knows there is no HEAD branch to mark.
    private static func parseCurrentBranch(_ result: GitResult) -> String? {
        guard result.isSuccess else { return nil }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Parse `git rev-parse --is-shallow-repository` output. Prints either
    /// `true\n` or `false\n`; default to false on any parse failure.
    private static func parseShallow(_ result: GitResult) -> Bool {
        guard result.isSuccess else { return false }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed == "true"
    }
}
