import Foundation
import OSLog

/// Kind of git repository discovered on disk.
enum RepoKind: Equatable {
    /// Regular repository — the scanned directory contains a `.git/` subdir
    /// (or a gitlink file pointing at one, for worktrees/submodules).
    case workTree
    /// Bare repository — the scanned directory IS the git dir: it contains
    /// a `HEAD` file plus an `objects/` subdir (see `git init --bare`).
    case bare
}

/// Depth-1 repo discovery across configured root directories.
///
/// Scanning strategy (per `library/git-cli-integration.md` §1):
///
/// - Walk each root at depth 1 only. Nesting is opt-in: users configure a
///   deeper root in Settings instead of paying an unbounded recursion cost.
/// - Detect work-tree repos by a `.git` entry (dir or gitlink file) inside
///   each candidate directory.
/// - Detect bare repos by the `HEAD` + `objects/` signature.
/// - Never shell out to `git` per directory. The default `~/Developer` tree
///   can contain hundreds of entries; subprocess-per-dir adds hundreds of ms.
/// - Missing roots are logged and skipped, never thrown — scan returns the
///   subset that succeeded (VAL-REPO-005).
///
/// Fulfills: VAL-REPO-001, VAL-REPO-002, VAL-REPO-005, VAL-REPO-006.
enum RepoScanner {
    private static let logger = Logger(subsystem: "nl.rb2.kite", category: "repo")

    /// Scan each root at depth 1 and return every discovered repo.
    ///
    /// Roots are scanned in parallel via a task group; entries within each
    /// root are enumerated sequentially (they share an inode cursor —
    /// parallelising would only increase syscall pressure). Returned list
    /// is sorted by `rootPath` (stable, in the order roots were provided),
    /// then by `displayName` case-insensitively within each root.
    static func scan(roots: [URL]) async -> [DiscoveredRepo] {
        guard !roots.isEmpty else { return [] }

        // Capture indexed roots so we can preserve caller-provided root order
        // in the final output while still scanning in parallel.
        let indexed = roots.enumerated().map { ($0.offset, $0.element) }

        let grouped: [(Int, [DiscoveredRepo])] = await withTaskGroup(
            of: (Int, [DiscoveredRepo]).self
        ) { group in
            for (index, root) in indexed {
                group.addTask {
                    (index, scanRoot(root))
                }
            }
            var results: [(Int, [DiscoveredRepo])] = []
            for await pair in group {
                results.append(pair)
            }
            return results
        }

        return grouped
            .sorted { $0.0 < $1.0 }
            .flatMap(\.1)
    }

    /// Cheap FS check: is `url` a git repo, and of what kind? Does not shell
    /// out to git. Used by both the scanner and anyone needing a quick
    /// classification (e.g. drag-and-drop import in later milestones).
    static func isRepo(_ url: URL) -> RepoKind? {
        let fm = FileManager.default

        // Work tree: `.git` is either a directory or a gitlink file (worktrees
        // and submodules produce a plain file whose contents point at the
        // shared git dir — both are valid repos for our purposes).
        let gitPath = url.appendingPathComponent(".git").path
        var gitIsDir: ObjCBool = false
        if fm.fileExists(atPath: gitPath, isDirectory: &gitIsDir) {
            return .workTree
        }

        // Bare: `HEAD` file + `objects/` directory at the scanned path itself.
        // We deliberately check both to avoid misclassifying every directory
        // that happens to contain a `HEAD` file.
        let headPath = url.appendingPathComponent("HEAD").path
        var headIsDir: ObjCBool = false
        let objectsPath = url.appendingPathComponent("objects").path
        var objectsIsDir: ObjCBool = false
        let hasHead = fm.fileExists(atPath: headPath, isDirectory: &headIsDir) && !headIsDir.boolValue
        let hasObjects = fm.fileExists(atPath: objectsPath, isDirectory: &objectsIsDir) && objectsIsDir.boolValue
        if hasHead, hasObjects {
            return .bare
        }

        return nil
    }

    // MARK: - Private

    /// Scan a single root directory at depth 1.
    private static func scanRoot(_ root: URL) -> [DiscoveredRepo] {
        let fm = FileManager.default
        let standardized = root.standardizedFileURL

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: standardized.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            logger.error("RepoScanner: skipping missing or non-directory root \(standardized.path, privacy: .public)")
            return []
        }

        let children: [URL]
        do {
            children = try fm.contentsOfDirectory(
                at: standardized,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        } catch {
            logger.error("""
            RepoScanner: failed to enumerate \(standardized.path, privacy: .public): \
            \(error.localizedDescription, privacy: .public)
            """)
            return []
        }

        var discovered: [DiscoveredRepo] = []
        discovered.reserveCapacity(children.count)

        for child in children {
            // Defensive: `skipsHiddenFiles` already drops dotfiles, but resolve
            // symlinks to get stable display names and keep key stability.
            let entry = child.standardizedFileURL

            // Skip non-directory entries (regular files in the root level are
            // not repos at depth 1).
            var entryIsDir: ObjCBool = false
            guard fm.fileExists(atPath: entry.path, isDirectory: &entryIsDir), entryIsDir.boolValue else {
                continue
            }

            guard let kind = isRepo(entry) else { continue }

            discovered.append(DiscoveredRepo(
                url: entry,
                displayName: entry.lastPathComponent,
                rootPath: standardized,
                isBare: kind == .bare
            ))
        }

        discovered.sort { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        return discovered
    }
}
