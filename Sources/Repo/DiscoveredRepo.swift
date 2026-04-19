import Foundation

/// A git repository located by `RepoScanner` on the local filesystem.
///
/// Produced by depth-1 scanning of each configured root. `url` is the
/// work-tree path for a normal repo, or the `.git`-directory path for a bare
/// repo. `rootPath` is the scan root this repo was discovered under so the
/// sidebar can group repos by their originating root (VAL-REPO-003).
struct DiscoveredRepo: Equatable, Hashable, Identifiable {
    /// Absolute path of the work tree (or of the bare `.git` directory).
    let url: URL
    /// Display name — last path component of `url`.
    let displayName: String
    /// The scan root under which this repo was discovered.
    let rootPath: URL
    /// True for bare repos (`git init --bare`). Bare repos have no worktree,
    /// so downstream UI shows a read-only message (VAL-REPO-006).
    let isBare: Bool

    var id: URL {
        url
    }
}
