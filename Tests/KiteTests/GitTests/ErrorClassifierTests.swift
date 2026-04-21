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
            ),
            ClassifierCase(
                stderr: """
                remote: error: hook declined: you cannot commit to main outside office hours
                remote: error: failed to push some refs to 'git@github.com:org/repo'
                 ! [remote rejected] main -> main (hook declined)
                error: failed to push some refs to 'git@github.com:org/repo'
                """,
                expected: .hookRejectedKind
            ),
            ClassifierCase(
                stderr: """
                remote: error: GH006: Protected branch update failed for refs/heads/main.
                remote: error: Changes must be made through a pull request.
                To github.com:org/repo.git
                 ! [remote rejected] main -> main (protected branch hook declined)
                error: failed to push some refs to 'github.com:org/repo.git'
                """,
                expected: .protectedBranchKind
            ),
            ClassifierCase(
                stderr: """
                remote: error: denying non-fast-forward refs/heads/main (you should pull first)
                 ! [remote rejected] main -> main (denying non-fast-forward)
                error: failed to push some refs to 'git@server.local:repo'
                """,
                expected: .remoteRejectedKind
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
             (.some(.notAGitRepository), .notARepoKind),
             (.some(.hookRejected), .hookRejectedKind),
             (.some(.protectedBranch), .protectedBranchKind),
             (.some(.remoteRejected), .remoteRejectedKind):
            break
        default:
            Issue.record("Expected \(fixture.expected) for stderr: \(fixture.stderr), got \(String(describing: error))")
        }
    }

    @Test("hookRejected extracts the reason text after 'hook declined:'")
    func hookRejectedReasonExtraction() {
        let stderr = """
        remote: error: hook declined: you cannot commit to main outside office hours
        remote: error: failed to push some refs to 'git@github.com:org/repo'
         ! [remote rejected] main -> main (hook declined)
        error: failed to push some refs to 'git@github.com:org/repo'
        """
        let error = ErrorClassifier.classify(stderr: stderr, exitCode: 1)
        guard case let .hookRejected(detail) = error else {
            Issue.record("Expected .hookRejected, got \(String(describing: error))")
            return
        }
        #expect(detail == "you cannot commit to main outside office hours")
    }

    @Test("protectedBranch extracts the actionable follow-up line from a GH006 rejection")
    func protectedBranchDetailExtraction() {
        let stderr = """
        remote: error: GH006: Protected branch update failed for refs/heads/main.
        remote: error: Changes must be made through a pull request.
        To github.com:org/repo.git
         ! [remote rejected] main -> main (protected branch hook declined)
        error: failed to push some refs to 'github.com:org/repo.git'
        """
        let error = ErrorClassifier.classify(stderr: stderr, exitCode: 1)
        guard case let .protectedBranch(detail) = error else {
            Issue.record("Expected .protectedBranch, got \(String(describing: error))")
            return
        }
        #expect(detail == "Changes must be made through a pull request.")
    }

    @Test("remoteRejected captures a reasonable detail for a generic denial")
    func remoteRejectedDetailExtraction() {
        let stderr = """
        remote: error: denying non-fast-forward refs/heads/main (you should pull first)
         ! [remote rejected] main -> main (denying non-fast-forward)
        error: failed to push some refs to 'git@server.local:repo'
        """
        let error = ErrorClassifier.classify(stderr: stderr, exitCode: 1)
        guard case let .remoteRejected(detail) = error else {
            Issue.record("Expected .remoteRejected, got \(String(describing: error))")
            return
        }
        #expect(detail.lowercased().contains("denying"))
    }

    @Test("hookRejected pattern beats the bare [remote rejected] footer")
    func hookRejectedBeatsRemoteRejected() {
        let stderr = """
        remote: error: pre-receive hook declined
        remote: error: hook declined: commit message format invalid
         ! [remote rejected] main -> main (pre-receive hook declined)
        error: failed to push some refs to 'git@host:org/repo'
        """
        let error = ErrorClassifier.classify(stderr: stderr, exitCode: 1)
        if case .hookRejected = error { return }
        Issue.record("Expected .hookRejected to win over .remoteRejected, got \(String(describing: error))")
    }

    @Test("protectedBranch pattern beats the bare [remote rejected] footer")
    func protectedBranchBeatsRemoteRejected() {
        let stderr = """
        remote: error: GH006: Protected branch update failed for refs/heads/main.
        remote: error: At least 1 approving review is required.
         ! [remote rejected] main -> main (protected branch hook declined)
        error: failed to push some refs to 'github.com:org/repo.git'
        """
        let error = ErrorClassifier.classify(stderr: stderr, exitCode: 1)
        if case .protectedBranch = error { return }
        Issue.record("Expected .protectedBranch to win over .remoteRejected, got \(String(describing: error))")
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
    case hookRejectedKind
    case protectedBranchKind
    case remoteRejectedKind
}

struct ClassifierCase: CustomStringConvertible {
    let stderr: String
    let expected: ClassifierKind

    var description: String {
        let head = stderr.split(whereSeparator: { $0 == "\n" }).first.map(String.init) ?? stderr
        return "\(expected): \(head)"
    }
}
