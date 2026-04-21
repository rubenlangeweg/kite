import Foundation

/// Domain errors produced by the git engine. Each case carries enough context
/// to render a user-facing toast and (for failures) the captured stderr.
enum GitError: Error, Equatable {
    case missingExecutable(String)
    case processFailed(exitCode: Int32, stderr: String)
    case auth(String)
    case nonFastForward(String)
    case noUpstream(String)
    case dirtyWorkingTree(String)
    case networkUnreachable(String)
    case notAGitRepository(String)
    case remoteRejected(String)
    case hookRejected(String)
    case protectedBranch(String)
    case cancelled
}

extension GitError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .missingExecutable(detail):
            return "Git is not available: \(detail)"
        case let .processFailed(code, stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "git exited with code \(code).\(trimmed.isEmpty ? "" : " " + trimmed)"
        case let .auth(detail):
            return "Authentication failed. \(detail)"
        case let .nonFastForward(detail):
            return "Non-fast-forward update. \(detail)"
        case let .noUpstream(detail):
            return "No upstream branch. \(detail)"
        case let .dirtyWorkingTree(detail):
            return "Uncommitted changes would be overwritten. \(detail)"
        case let .networkUnreachable(detail):
            return "Network unreachable. \(detail)"
        case let .notAGitRepository(detail):
            return "Not a git repository. \(detail)"
        case let .remoteRejected(detail):
            return "Remote rejected the push: \(detail). Check the server-side response — usually a policy or hook rejection."
        case let .hookRejected(detail):
            return "A pre-receive or update hook rejected the push: \(detail)"
        case let .protectedBranch(detail):
            return "Branch is protected on the remote: \(detail). Open a pull request or push to a different branch."
        case .cancelled:
            return "Operation cancelled."
        }
    }
}
