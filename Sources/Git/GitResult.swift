import Foundation

/// Captured result of a one-shot `Git.run` invocation.
struct GitResult: Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var isSuccess: Bool {
        exitCode == 0
    }

    /// Throw a typed `GitError` if this result represents a failure. Uses the
    /// provided classifier to map stderr patterns to specific cases; falls
    /// back to `.processFailed` otherwise.
    func throwIfFailed(classifier: (_ stderr: String, _ exitCode: Int32) -> GitError? = ErrorClassifier.classify) throws {
        guard !isSuccess else { return }
        if let classified = classifier(stderr, exitCode) {
            throw classified
        }
        throw GitError.processFailed(exitCode: exitCode, stderr: stderr)
    }
}
