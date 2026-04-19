import Foundation

/// A single ref attached to a commit. Built from `for-each-ref` output and
/// joined with commit SHAs for branch-pill rendering.
///
/// Symbolic `HEAD` pseudo-refs (e.g. `refs/remotes/origin/HEAD`) are NOT
/// represented — the parser filters them out.
enum RefKind: Equatable {
    case localBranch(String)
    case remoteBranch(remote: String, branch: String)
    case tag(String)
    case head
}
