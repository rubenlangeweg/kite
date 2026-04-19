import Foundation
import Testing
@testable import Kite

@Suite("ErrorClassifier")
struct ErrorClassifierTests {
    @Test(
        "classifies known git stderr patterns",
        arguments: [
            ClassifierCase(
                stderr: "fatal: Authentication failed for 'https://github.com/foo/bar.git/'",
                expected: .authKind
            ),
            ClassifierCase(
                stderr: "fatal: could not read Username for 'https://github.com': terminal prompts disabled",
                expected: .authKind
            ),
            ClassifierCase(
                stderr: "git@github.com: Permission denied (publickey).\nfatal: Could not read from remote repository.",
                expected: .authKind
            ),
            ClassifierCase(
                stderr: """
                To github.com:foo/bar.git
                 ! [rejected]        main -> main (non-fast-forward)
                error: failed to push some refs to 'github.com:foo/bar.git'
                """,
                expected: .nonFastForwardKind
            ),
            ClassifierCase(
                stderr: "fatal: The current branch feature/xyz has no upstream branch.",
                expected: .noUpstreamKind
            ),
            ClassifierCase(
                stderr: """
                error: Your local changes to the following files would be overwritten by checkout:
                    README.md
                Please commit your changes or stash them before you switch branches.
                Aborting
                """,
                expected: .dirtyWorkingTreeKind
            ),
            ClassifierCase(
                stderr: "fatal: unable to access 'https://bogus.invalid/': Could not resolve host: bogus.invalid",
                expected: .networkUnreachableKind
            ),
            ClassifierCase(
                stderr: "fatal: not a git repository (or any of the parent directories): .git",
                expected: .notARepoKind
            )
        ]
    )
    func classifies(_ fixture: ClassifierCase) {
        let error = ErrorClassifier.classify(stderr: fixture.stderr, exitCode: 128)
        switch (error, fixture.expected) {
        case (.some(.auth), .authKind),
             (.some(.nonFastForward), .nonFastForwardKind),
             (.some(.noUpstream), .noUpstreamKind),
             (.some(.dirtyWorkingTree), .dirtyWorkingTreeKind),
             (.some(.networkUnreachable), .networkUnreachableKind),
             (.some(.notAGitRepository), .notARepoKind):
            break
        default:
            Issue.record("Expected \(fixture.expected) for stderr: \(fixture.stderr), got \(String(describing: error))")
        }
    }

    @Test("returns nil for unknown stderr")
    func returnsNilForUnknown() {
        let stderr = "fatal: something bizarre that we haven't mapped yet\n"
        #expect(ErrorClassifier.classify(stderr: stderr, exitCode: 1) == nil)
    }

    @Test("GitResult.throwIfFailed maps classified stderr to typed error")
    func throwIfFailedMapsStderr() {
        let result = GitResult(
            exitCode: 128,
            stdout: "",
            stderr: "fatal: Authentication failed for 'https://example.com/repo.git/'"
        )
        do {
            try result.throwIfFailed()
            Issue.record("Expected throwIfFailed to throw")
        } catch let error as GitError {
            if case .auth = error { return }
            Issue.record("Expected .auth, got \(error)")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("GitResult.throwIfFailed falls back to .processFailed for unknown stderr")
    func throwIfFailedFallback() {
        let result = GitResult(exitCode: 2, stdout: "", stderr: "weird failure we don't recognize")
        do {
            try result.throwIfFailed()
            Issue.record("Expected throw")
        } catch let error as GitError {
            if case let .processFailed(code, _) = error {
                #expect(code == 2)
                return
            }
            Issue.record("Expected .processFailed, got \(error)")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("GitResult.throwIfFailed is a no-op on success")
    func throwIfFailedNoOpOnSuccess() throws {
        let result = GitResult(exitCode: 0, stdout: "ok", stderr: "")
        try result.throwIfFailed()
    }
}

/// Categories used so the `arguments:` macro can compare at enum-case level
/// without having to match associated-value text.
enum ClassifierKind {
    case authKind
    case nonFastForwardKind
    case noUpstreamKind
    case dirtyWorkingTreeKind
    case networkUnreachableKind
    case notARepoKind
}

struct ClassifierCase: CustomStringConvertible {
    let stderr: String
    let expected: ClassifierKind

    var description: String {
        let head = stderr.split(whereSeparator: { $0 == "\n" }).first.map(String.init) ?? stderr
        return "\(expected): \(head)"
    }
}
