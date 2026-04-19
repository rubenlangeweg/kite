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

        // Non-fast-forward push/pull.
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
}
