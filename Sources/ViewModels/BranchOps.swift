import Foundation
import Observation
import OSLog

/// App-wide service that runs local branch operations (create + switch) on the
/// focused repo and routes outcomes through `ToastCenter`.
///
/// Scope:
///   - `createBranch(_:on:)` → `git switch -c <name>` against the focused repo.
///     Validates the name with `BranchNameValidator` first; a rejected name
///     never reaches `Process`.
///   - `switchToLocal(_:on:)` → `git switch <name>` on the focused repo.
///   - `switchToRemote(remote:branch:existingLocal:on:)` → if an existing local
///     already tracks `<remote>/<branch>`, just `git switch` to it (caller
///     passes the local shortName via `existingLocal`); otherwise
///     `git switch -c <branch> --track <remote>/<branch>`.
///
/// Design:
///   - Each op is serialised against the focused repo via `focus.queue.run`
///     so two rapid triggers execute sequentially on the same `.git/`
///     directory (VAL-NET-009 pattern).
///   - Dirty-tree errors produce the documented
///     "Uncommitted changes — stash or commit in terminal before switching."
///     toast (VAL-BRANCHOP-006).
///   - On success a green auto-dismissing toast is enqueued; on classified
///     failure a red sticky toast with stderr attached.
///
/// Never passes the two-dash "force" or "force-with-lease" flags —
/// `SecurityInvariantsTests` grep-proves this across the entire source
/// tree (VAL-SEC-001).
///
/// Fulfills: VAL-BRANCHOP-001, VAL-BRANCHOP-002, VAL-BRANCHOP-003,
/// VAL-BRANCHOP-004, VAL-BRANCHOP-005, VAL-BRANCHOP-006,
/// VAL-SEC-007 (validator + argv Process).
@Observable
@MainActor
final class BranchOps {
    @ObservationIgnored
    private let toasts: ToastCenter

    @ObservationIgnored
    private static let logger = Logger(subsystem: "nl.rb2.kite", category: "git")

    /// Shared dirty-tree copy for switch flows. Centralised so create-branch
    /// and both switch-branch paths surface the identical UX string.
    @ObservationIgnored
    static let dirtyTreeMessage: String =
        "Uncommitted changes — stash or commit in terminal before switching."

    init(toasts: ToastCenter) {
        self.toasts = toasts
    }

    // MARK: - Create

    /// Run `git switch -c <name>` against the focused repo. Returns `true` on
    /// success, `false` when the validator rejected the name or the subprocess
    /// failed. The caller is expected to dismiss the sheet on either outcome
    /// — the toast surface carries the user feedback.
    @discardableResult
    func createBranch(_ name: String, on focus: RepoFocus) async -> Bool {
        if let err = BranchNameValidator.validate(name) {
            let detail = err.errorDescription ?? "Invalid branch name"
            toasts.error("Invalid branch name: \(detail)")
            Self.logger.error(
                "BranchOps.createBranch rejected \(name, privacy: .public): \(detail, privacy: .public)"
            )
            return false
        }
        return await runSwitch(
            args: ["switch", "-c", name],
            on: focus,
            successMessage: "Created branch \(name)",
            fallbackFailure: "Failed to create branch",
            logContext: "BranchOps.createBranch(\(name))"
        )
    }

    // MARK: - Switch

    /// Run `git switch <name>` on the focused repo.
    ///
    /// VAL-BRANCHOP-004: double-clicking a local branch drives this entry
    /// point. Dirty-tree failures surface the documented copy; every other
    /// classified failure falls through to the classified toast.
    @discardableResult
    func switchToLocal(_ name: String, on focus: RepoFocus) async -> Bool {
        await runSwitch(
            args: ["switch", name],
            on: focus,
            successMessage: "Switched to \(name)",
            fallbackFailure: "Failed to switch branch",
            logContext: "BranchOps.switchToLocal(\(name))"
        )
    }

    /// Switch to a remote-tracking branch, creating a local tracker if one
    /// doesn't already exist.
    ///
    /// - If `existingLocal` is non-nil the caller has determined that a local
    ///   branch (of that name) already tracks `<remote>/<branch>`, so we
    ///   delegate to `switchToLocal` — avoids spawning `git switch -c` on a
    ///   name that already exists (which would surface as "already exists").
    /// - Otherwise run `git switch -c <branch> --track <remote>/<branch>`.
    ///
    /// The caller (view) computes `existingLocal` by scanning
    /// `BranchListModel.local` for any branch whose `upstream` equals
    /// `"\(remote)/\(branch)"`. Keeping the scan in the view keeps this
    /// method's surface simple and branch-list-agnostic.
    ///
    /// VAL-BRANCHOP-005.
    @discardableResult
    func switchToRemote(
        remote: String,
        branch: String,
        existingLocal: String?,
        on focus: RepoFocus
    ) async -> Bool {
        if let existing = existingLocal {
            return await switchToLocal(existing, on: focus)
        }
        let trackingRef = "\(remote)/\(branch)"
        return await runSwitch(
            args: ["switch", "-c", branch, "--track", trackingRef],
            on: focus,
            successMessage: "Switched to \(branch) (tracking \(trackingRef))",
            fallbackFailure: "Failed to switch to remote branch",
            logContext: "BranchOps.switchToRemote(\(trackingRef))"
        )
    }

    // MARK: - Private runner

    /// Shared implementation for every `git switch` flavour. Serialises on
    /// `focus.queue`, runs `Git.run`, classifies errors, and routes toasts.
    private func runSwitch(
        args: [String],
        on focus: RepoFocus,
        successMessage: String,
        fallbackFailure: String,
        logContext: String
    ) async -> Bool {
        let repoURL = focus.repo.url
        do {
            try await focus.queue.run { @Sendable in
                let result = try await Git.run(args: args, cwd: repoURL)
                try result.throwIfFailed(classifier: ErrorClassifier.classify)
            }
            toasts.success(successMessage)
            return true
        } catch let gitError as GitError {
            let (message, detail) = messageFor(error: gitError, fallback: fallbackFailure)
            toasts.error(message, detail: detail)
            Self.logger.error("\(logContext, privacy: .public) failed: \(message, privacy: .public)")
            return false
        } catch is CancellationError {
            // Cancellation is normal (focus swap, window close) — no toast.
            return false
        } catch {
            let message = error.localizedDescription.isEmpty
                ? fallbackFailure
                : "\(fallbackFailure): \(error.localizedDescription)"
            toasts.error(message)
            Self.logger.error("\(logContext, privacy: .public) failed: \(message, privacy: .public)")
            return false
        }
    }

    /// Map a classified `GitError` to user-facing toast copy + optional
    /// stderr detail for the click-to-expand panel.
    private func messageFor(error: GitError, fallback: String) -> (String, String?) {
        switch error {
        case let .dirtyWorkingTree(detail):
            // VAL-BRANCHOP-006: documented consistent copy for any switch flow.
            return (Self.dirtyTreeMessage, detail.isEmpty ? nil : detail)
        case let .processFailed(_, stderr):
            // Most common non-classified failure: duplicate branch. git writes:
            //   "fatal: A branch named '<name>' already exists."
            // Preserve git's stderr verbatim for the toast body.
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return (fallback, nil)
            }
            return (firstLine(of: trimmed), trimmed)
        default:
            let desc = (error as LocalizedError).errorDescription ?? fallback
            return (desc, nil)
        }
    }

    private func firstLine(of blob: String) -> String {
        blob.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .first
            .map(String.init) ?? blob
    }
}
