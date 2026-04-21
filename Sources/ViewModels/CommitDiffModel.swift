import Foundation
import Observation
import OSLog

/// Metadata header for a single commit — what `CommitHeaderView` renders above
/// the file diffs in the selected-commit diff pane.
///
/// Parsed from a single `git show --format=...` payload alongside the patch
/// body so we only pay one subprocess round-trip per click. `shortSHA` is the
/// first 7 chars; `body` may be empty (one-line commits) and is the fields
/// beyond the subject.
struct CommitHeader: Equatable {
    let sha: String
    let shortSHA: String
    let authorName: String
    let authorEmail: String
    let authoredAt: Date
    let subject: String
    let body: String
    let refs: [RefKind]
}

/// View model backing `CommitDiffView` — loads the header + file diffs for a
/// single commit via `git show <sha>` (VAL-DIFF-003, VAL-GRAPH-009).
///
/// Single-subprocess design: `git show --format=format:<fields> --patch <sha>`
/// emits the requested header fields (NUL-separated) on the first line,
/// followed by a blank line, followed by the unified-diff patch. We split on
/// the first `\ndiff --git ` boundary (falling back to the first blank line for
/// empty-patch commits) so a commit body that itself contains blank lines
/// doesn't fool the splitter. M1-fix-git-run-drain's concurrent pipe drain
/// makes this safe for arbitrarily large commits — large commits are a
/// must-work case, not an edge case (VAL-DIFF-006).
///
/// Cancel-prior-Task + SHA de-dup discipline:
///   - Repeated calls to `load(sha:)` with the same SHA are a no-op — the
///     model tracks `currentSHA` and returns early, preventing a wasted
///     subprocess on every re-render of `CommitDiffView` (SwiftUI's
///     `.task(id:)` may invoke us more than once with the same identity).
///   - A new SHA cancels the in-flight load via `loadTask?.cancel()`, matching
///     the per-focus fan-out discipline in INTERFACES.md §4.
///
/// Error handling: any git failure is captured in `lastError` (localized) and
/// logged via `Logger(category: "diff")` per AGENTS.md no-silent-swallow rule.
@Observable
@MainActor
final class CommitDiffModel {
    private(set) var header: CommitHeader?
    private(set) var files: [FileDiff] = []
    private(set) var isLoading: Bool = false
    private(set) var lastError: String?

    @ObservationIgnored
    private static let logger = Logger(subsystem: "nl.rb2.kite", category: "diff")

    /// Handle to the in-flight load so a subsequent load can cancel the
    /// previous one. Never touched off the main actor.
    @ObservationIgnored
    private var loadTask: Task<Void, Never>?

    /// SHA of the commit this model is currently showing (or currently
    /// loading). Set synchronously at the start of `load(sha:)` so a
    /// same-SHA re-invocation returns immediately instead of spinning up a
    /// second subprocess.
    @ObservationIgnored
    private var currentSHA: String?

    init() {}

    /// Load the header + file diffs for `sha`. De-duplicates on the current
    /// SHA; cancels any prior in-flight load for a different SHA. Awaits the
    /// underlying task so callers can sequence against completion.
    func load(sha: String, for focus: RepoFocus) async {
        // De-dup: same SHA as the one we just loaded (or are loading) — skip.
        if sha == currentSHA { return }
        currentSHA = sha

        loadTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await performLoad(sha: sha, for: focus)
        }
        loadTask = task
        await task.value
    }

    /// Clear every piece of observable state. Used when the diff pane
    /// switches back to the working-copy diff or the focused repo unmounts.
    func clear() {
        loadTask?.cancel()
        loadTask = nil
        currentSHA = nil
        header = nil
        files = []
        isLoading = false
        lastError = nil
    }

    // MARK: - Internals

    private func performLoad(sha: String, for focus: RepoFocus) async {
        isLoading = true
        defer { isLoading = false }

        let repoURL = focus.repo.url
        do {
            let (parsedHeader, parsedFiles) = try await focus.queue.run {
                let showResult = try await Git.run(
                    args: Self.showArgs(for: sha),
                    cwd: repoURL
                )
                try showResult.throwIfFailed()
                let refsResult = try await Git.run(
                    args: [
                        "for-each-ref",
                        "--format=%(objectname) %(refname)%00%(*objectname)",
                        "--points-at", sha
                    ],
                    cwd: repoURL
                )
                let refsMap: [String: [RefKind]] = refsResult.isSuccess
                    ? ((try? ForEachRefParser.parse(refsResult.stdout)) ?? [:])
                    : [:]
                let (headerPart, diffPart) = Self.splitShowOutput(showResult.stdout)
                let headerFields = try Self.parseHeaderFields(headerPart, sha: sha, refsMap: refsMap)
                let filesParsed = try DiffParser.parse(diffPart)
                return (headerFields, filesParsed)
            }

            try Task.checkCancellation()

            header = parsedHeader
            files = parsedFiles
            lastError = nil
        } catch is CancellationError {
            // Cancellation is normal (follow-up load superseded us). Don't
            // clobber state — the successor load (or `clear()`) repopulates.
            return
        } catch {
            Self.logger.error("""
            CommitDiffModel.load failed for \(sha, privacy: .public) in \
            \(repoURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)
            """)
            header = nil
            files = []
            lastError = error.localizedDescription
        }
    }

    /// Build the `git show` arg vector. `%x00` is the NUL byte — a separator
    /// git never emits as data, which lets us split cleanly even when any of
    /// the header fields contain spaces or internal newlines (`%b` does).
    /// The trailing `%n` guarantees the patch starts on its own line.
    static func showArgs(for sha: String) -> [String] {
        [
            "show",
            "--no-color",
            "--format=format:%H%x00%h%x00%an%x00%ae%x00%at%x00%s%x00%b%n",
            "--patch",
            sha
        ]
    }

    /// Split git-show stdout into (headerBlob, diffBlob).
    ///
    /// Prefers the `\ndiff --git ` boundary (always present when the commit
    /// touches at least one file). For commits with an empty tree change
    /// (merge commits with no file deltas, `--allow-empty`), git prints only
    /// the formatted header — no patch — so we return the whole input as
    /// the header and an empty diff.
    ///
    /// The `\ndiff --git ` substring must land on its own line to be a valid
    /// boundary: a commit body that quotes a literal `diff --git a/x b/y`
    /// would otherwise false-match. We keep the leading `\n` in the match so
    /// a pathological subject line like `diff --git a/...` (which cannot
    /// appear at column 0 of the header because `%s` is the fifth NUL-
    /// separated field, not the first) stays on the header side.
    nonisolated static func splitShowOutput(_ raw: String) -> (header: String, diff: String) {
        if let range = raw.range(of: "\ndiff --git ") {
            let header = String(raw[..<range.lowerBound])
            // Keep the `diff --git ` prefix on the diff side — DiffParser
            // expects each file to start with that line.
            let diff = String(raw[raw.index(after: range.lowerBound)...])
            return (header, diff)
        }
        return (raw, "")
    }

    /// Parse the NUL-separated header payload into a `CommitHeader`.
    ///
    /// Expected field order (matches `showArgs`):
    ///   0: %H  — full SHA
    ///   1: %h  — short SHA (git's own abbreviation)
    ///   2: %an — author name
    ///   3: %ae — author email
    ///   4: %at — UNIX timestamp (seconds)
    ///   5: %s  — subject line
    ///   6: %b  — body (possibly empty, possibly multi-line)
    ///
    /// `%b` may contain its own `\n` characters; we pass the raw String
    /// through, trimming only trailing whitespace (so a body that git auto-
    /// terminates with a blank line doesn't render with a trailing empty line
    /// in the UI).
    nonisolated static func parseHeaderFields(
        _ raw: String,
        sha _: String,
        refsMap: [String: [RefKind]]
    ) throws -> CommitHeader {
        // Drop the trailing newline git appends before the blank separator.
        // Keep internal newlines (they belong to `%b`).
        let fields = raw.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 6 else {
            throw ParseError.malformedLine(raw)
        }
        let full = fields[0]
        let short = fields[1].isEmpty ? String(full.prefix(7)) : fields[1]
        let authorName = fields[2]
        let authorEmail = fields[3]
        let timestampStr = fields[4]
        let subject = fields[5]
        let bodyRaw = fields.count >= 7 ? fields[6] : ""
        let body = bodyRaw.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let timestamp = TimeInterval(timestampStr) else {
            throw ParseError.malformedLine(raw)
        }
        let authoredAt = Date(timeIntervalSince1970: timestamp)
        let refs = refsMap[full] ?? []

        return CommitHeader(
            sha: full,
            shortSHA: short,
            authorName: authorName,
            authorEmail: authorEmail,
            authoredAt: authoredAt,
            subject: subject,
            body: body,
            refs: refs
        )
    }
}
