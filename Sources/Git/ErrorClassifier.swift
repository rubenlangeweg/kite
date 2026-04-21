import Foundation

/// Pure function mapping captured stderr + exit code to a typed `GitError`.
///
/// Returns `nil` when no pattern matches; callers should then surface the
/// generic `GitError.processFailed(exitCode:stderr:)` from `GitResult.throwIfFailed`.
///
/// Fulfills VAL-PARSE-007.
enum ErrorClassifier {
    /// Classify the tail of a git stderr blob. Only the stderr is inspected;
    /// exit code is accepted for future refinement but currently not branched
    /// on (stderr is the single reliable signal on Apple Git 2.50+).
    static func classify(stderr: String, exitCode _: Int32) -> GitError? {
        let lower = stderr.lowercased()
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)

        // Network / DNS first — some auth-y looking messages are actually
        // network errors ("could not resolve host") and we want to classify
        // them as networkUnreachable not auth.
        if lower.contains("could not resolve host") ||
            lower.contains("unable to access") ||
            lower.contains("failed to connect to") ||
            lower.contains("network is unreachable")
        {
            return .networkUnreachable(firstLine(of: trimmed))
        }

        // Auth failure (HTTPS or SSH).
        if lower.contains("authentication failed") ||
            lower.contains("could not read username") ||
            lower.contains("could not read from remote repository") ||
            lower.contains("permission denied (publickey)") ||
            lower.contains("terminal prompts disabled")
        {
            return .auth(firstLine(of: trimmed))
        }

        // Push rejection patterns come before the plain non-fast-forward check:
        // a server-side `denying non-fast-forward` should surface as .remoteRejected
        // (actionable: the server's policy), not a local .nonFastForward hint.
        // Order within this block: most specific first.

        // Protected branch (GitHub's GH006 + generic "protected branch hook declined").
        if lower.contains("gh006: protected branch update failed") ||
            lower.contains("protected branch update failed") ||
            lower.contains("protected branch hook declined")
        {
            return .protectedBranch(protectedBranchDetail(stderr: stderr, trimmed: trimmed))
        }

        // Hook rejection (pre-receive or update). More specific than the generic
        // "remote rejected" footer; must be checked before it.
        if lower.contains("pre-receive hook declined") ||
            lower.contains("update hook declined") ||
            lower.contains("hook declined")
        {
            return .hookRejected(hookDeclinedReason(stderr: stderr, trimmed: trimmed))
        }

        // Generic server-side rejection (catch-all). Keep last among push errors.
        if lower.contains("[remote rejected]") ||
            lower.contains("remote rejected") ||
            lower.contains("remote: error: denying")
        {
            return .remoteRejected(remoteRejectedReason(stderr: stderr, trimmed: trimmed))
        }

        // Non-fast-forward push/pull (local-side hint — remote didn't explicitly reject).
        if lower.contains("non-fast-forward") ||
            lower.contains("updates were rejected because the tip of your current branch is behind") ||
            lower.contains("not possible to fast-forward")
        {
            return .nonFastForward(firstLine(of: trimmed))
        }

        // Missing upstream (push or pull).
        if lower.contains("has no upstream branch") ||
            lower.contains("there is no tracking information for the current branch")
        {
            return .noUpstream(firstLine(of: trimmed))
        }

        // Dirty working tree blocking switch/pull.
        if lower.contains("your local changes to the following files would be overwritten") ||
            lower.contains("please commit your changes or stash them before you")
        {
            return .dirtyWorkingTree(firstLine(of: trimmed))
        }

        // Not a git repo.
        if lower.contains("not a git repository") {
            return .notAGitRepository(firstLine(of: trimmed))
        }

        return nil
    }

    private static func firstLine(of blob: String) -> String {
        blob.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .first
            .map(String.init) ?? blob
    }

    /// Extract the hook's reason line. Looks for `remote: error: hook declined: <reason>`
    /// first; falls back to the first `remote: error:` line, then to the first non-empty line.
    private static func hookDeclinedReason(stderr: String, trimmed: String) -> String {
        let lines = stderr.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map(String.init)
        for line in lines {
            let lower = line.lowercased()
            if let range = lower.range(of: "hook declined:") {
                let suffix = line[range.upperBound...]
                let cleaned = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { return cleaned }
            }
        }
        for line in lines {
            let lower = line.lowercased()
            if lower.hasPrefix("remote: error:"), !lower.contains("failed to push") {
                let stripped = line
                    .replacingOccurrences(of: "remote: error:", with: "", options: [.caseInsensitive])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !stripped.isEmpty { return stripped }
            }
        }
        return firstLine(of: trimmed)
    }

    /// Extract the actionable detail for a GitHub-style protected branch rejection.
    /// Prefers the "Changes must be made through a pull request." style follow-up over the GH006 header.
    private static func protectedBranchDetail(stderr: String, trimmed: String) -> String {
        let lines = stderr.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map(String.init)
        for line in lines {
            let lower = line.lowercased()
            guard lower.hasPrefix("remote: error:") else { continue }
            if lower.contains("gh006") || lower.contains("protected branch update failed") { continue }
            let stripped = line
                .replacingOccurrences(of: "remote: error:", with: "", options: [.caseInsensitive])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !stripped.isEmpty { return stripped }
        }
        for line in lines {
            let lower = line.lowercased()
            if lower.contains("protected branch update failed") {
                let stripped = line
                    .replacingOccurrences(of: "remote: error:", with: "", options: [.caseInsensitive])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !stripped.isEmpty { return stripped }
            }
        }
        return firstLine(of: trimmed)
    }

    /// Extract the reason for a generic remote rejection. Prefers a `remote: error: denying ...`
    /// line, then the `[remote rejected] <ref> -> <ref> (<reason>)` parenthesised reason,
    /// then the first line.
    private static func remoteRejectedReason(stderr: String, trimmed: String) -> String {
        let lines = stderr.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map(String.init)
        for line in lines {
            let lower = line.lowercased()
            if lower.contains("remote: error: denying") {
                let stripped = line
                    .replacingOccurrences(of: "remote: error:", with: "", options: [.caseInsensitive])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !stripped.isEmpty { return stripped }
            }
        }
        for line in lines where line.lowercased().contains("[remote rejected]") {
            if let open = line.lastIndex(of: "("), let close = line.lastIndex(of: ")"), open < close {
                let inner = line[line.index(after: open) ..< close]
                let cleaned = inner.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { return cleaned }
            }
        }
        return firstLine(of: trimmed)
    }
}
