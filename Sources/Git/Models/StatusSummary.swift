import Foundation

/// Summary of `git status --porcelain=v2 --branch -z` output for the
/// working-copy header. Detached HEAD is surfaced via `detachedAt` (short
/// SHA) with `branch == nil`; a normal repo has `branch != nil` and
/// `detachedAt == nil`.
struct StatusSummary: Equatable {
    let branch: String?
    let detachedAt: String?
    let upstream: String?
    let ahead: Int
    let behind: Int
    let staged: Int
    let modified: Int
    let untracked: Int

    var isClean: Bool {
        staged == 0 && modified == 0 && untracked == 0
    }
}
