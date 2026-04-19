import Foundation

/// A local or remote-tracking branch with upstream metadata.
///
/// `ahead`/`behind` are nil when there is no upstream configured (distinct
/// from 0/0 which means "in sync"). `isGone` is true when the upstream was
/// deleted remotely (`[gone]` marker in `git branch`'s `upstream:track`
/// field). `isHead` is true for the currently-checked-out branch.
struct Branch: Equatable {
    let shortName: String
    let fullName: String
    let sha: String
    let upstream: String?
    let isRemote: Bool
    let remote: String?
    let ahead: Int?
    let behind: Int?
    let isGone: Bool
    let isHead: Bool
}
