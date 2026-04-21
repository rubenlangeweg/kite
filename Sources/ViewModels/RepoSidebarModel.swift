import Foundation
import Observation
import OSLog

/// View model wrapping `RepoScanner` + `PersistenceStore` for the multi-repo
/// sidebar (VAL-REPO-007/008/009).
///
/// Responsibilities:
///
/// - Aggregate default + user-added scan roots and produce a grouped,
///   sorted view of discovered repos (`discoveredByRoot`).
/// - Filter the persisted `pinnedRepos` list down to repos that actually
///   exist in the current scan (paths that don't match are kept in
///   persistence but simply excluded from the live `pinned` list).
/// - Own `selectedRepo` and round-trip the last-opened path through
///   `PersistenceStore` so a relaunch restores the previous selection.
@Observable
@MainActor
final class RepoSidebarModel {
    @ObservationIgnored
    private let persistence: PersistenceStore

    @ObservationIgnored
    private let repoStore: RepoStore?

    @ObservationIgnored
    private let rootsOverride: [URL]?

    @ObservationIgnored
    private let scanner: @Sendable ([URL]) async -> [DiscoveredRepo]

    @ObservationIgnored
    private static let logger = Logger(subsystem: "nl.rb2.kite", category: "ui")

    /// Repos grouped by their scan root, in root insertion order. Values are
    /// already sorted case-insensitively by `displayName` (RepoScanner guarantee).
    private(set) var discoveredByRoot: OrderedRepoGroups = .empty

    /// Live pinned repos — filtered to those currently discovered on disk.
    private(set) var pinned: [DiscoveredRepo] = []

    /// Currently selected repo. `nil` when no repo is focused (empty state
    /// or just after boot).
    private(set) var selectedRepo: DiscoveredRepo?

    /// Bindable selection property for SwiftUI `List(selection:)`.
    /// The getter returns `selectedRepo`; the setter routes through
    /// `select(_:)` so persistence + RepoStore side-effects fire.
    var selection: DiscoveredRepo? {
        get { selectedRepo }
        set { select(newValue) }
    }

    /// True while `refresh()` is running. Lets views render a subtle
    /// "scanning" affordance without showing the empty state prematurely.
    private(set) var isScanning: Bool = false

    /// - Parameters:
    ///   - persistence: shared store for pinned repos, extra roots, and last-opened path.
    ///   - repoStore: optional focus coordinator. When set, `select(_:)` forwards the
    ///     repo to `repoStore.focus(on:)` so the focused-repo lifecycle kicks in
    ///     (FSWatcher, GitQueue). Left nil in existing tests that only exercise
    ///     sidebar state.
    ///   - rootsOverride: optional hardcoded roots. Used by UI tests via the
    ///     `-KITE_FIXTURE_ROOTS` launch argument; in normal runs, nil.
    ///   - scanner: injection seam for tests. Production passes `RepoScanner.scan`.
    init(
        persistence: PersistenceStore,
        repoStore: RepoStore? = nil,
        rootsOverride: [URL]? = nil,
        scanner: @escaping @Sendable ([URL]) async -> [DiscoveredRepo] = RepoScanner.scan(roots:)
    ) {
        self.persistence = persistence
        self.repoStore = repoStore
        self.rootsOverride = rootsOverride
        self.scanner = scanner
    }

    // MARK: - Public API

    /// Re-scan roots and refresh derived state. Safe to call concurrently —
    /// re-entrant callers observe `isScanning` and should no-op, but the
    /// underlying scanner is idempotent so overlapping runs converge.
    func refresh() async {
        isScanning = true
        defer { isScanning = false }

        let roots = resolveRoots()
        let discovered = await scanner(roots)
        apply(discovered: discovered, rootOrder: roots)
    }

    /// Set the focused repo. Writes through to persistence so a relaunch
    /// restores the same selection (VAL-REPO-008), and — when a `RepoStore`
    /// has been injected — forwards to it so the per-repo FSWatcher / GitQueue
    /// lifecycle starts. `RepoStore` mirrors the last-opened path itself, so
    /// the persistence write here is redundant when one is present, but we
    /// keep it unconditional so the sidebar is self-sufficient even in
    /// repoStore-less configurations (unit tests, legacy wiring).
    func select(_ repo: DiscoveredRepo?) {
        selectedRepo = repo
        persistence.setLastOpenedRepo(repo?.url.path)
        repoStore?.focus(on: repo)
    }

    /// Pin a repo by absolute path. If it's currently discovered, it also
    /// appears in `pinned` immediately; otherwise it lives only in persistence
    /// until the next scan finds it.
    func pin(_ repo: DiscoveredRepo) {
        persistence.pin(repo.url.path)
        recomputePinned()
    }

    /// Unpin by absolute path. Matches both the discovered-repo path and the
    /// persisted-path to keep behaviour consistent when a repo has since
    /// vanished from disk.
    func unpin(_ repo: DiscoveredRepo) {
        persistence.unpin(repo.url.path)
        recomputePinned()
    }

    /// Reselect the last-opened repo if it still exists. Called once after
    /// the first refresh() resolves.
    func restoreLastSelection() async {
        guard let path = persistence.settings.lastOpenedRepo else { return }
        if let match = findDiscovered(byPath: path) {
            select(match)
        } else {
            // Repo has disappeared (drive unmounted, folder deleted). Keep
            // the last-opened path in persistence so it may come back later,
            // but don't force a selection now.
            Self.logger.info("Last-opened repo \(path, privacy: .public) not found in scan; leaving selection empty")
        }
    }

    // MARK: - Derived helpers

    /// Iterate `discoveredByRoot` in stable root order. Views use this rather
    /// than reaching into the `OrderedRepoGroups` internals.
    var rootSections: [(root: URL, repos: [DiscoveredRepo])] {
        discoveredByRoot.ordered
    }

    var hasAnyRepos: Bool {
        !discoveredByRoot.isEmpty || !pinned.isEmpty
    }

    /// Default scan root: `~/Developer`. RepoScanner gracefully skips it if
    /// the directory does not exist, so there's no need to guard here.
    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Developer")
    }

    // MARK: - Private

    private func resolveRoots() -> [URL] {
        if let override = rootsOverride {
            return override
        }
        var roots: [URL] = [Self.defaultRoot]
        for extra in persistence.settings.extraRoots {
            let url = URL(fileURLWithPath: (extra as NSString).expandingTildeInPath)
            // Avoid duplicate-root scans when the user re-adds `~/Developer`
            // explicitly — RepoScanner dedupes by rootPath in sort order, but
            // grouping would still produce two visually identical sections.
            if !roots.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) {
                roots.append(url)
            }
        }
        return roots
    }

    private func apply(discovered: [DiscoveredRepo], rootOrder: [URL]) {
        var groups = OrderedRepoGroups()
        // Preserve caller-provided root order even for roots that turned up
        // zero repos — they're still valid sections (helpful once the user
        // adds a root in Settings and hasn't populated it yet).
        for root in rootOrder {
            groups.appendRoot(root.standardizedFileURL)
        }
        for repo in discovered {
            groups.append(repo)
        }
        // Drop empty sections from the visible map; the scanner already
        // returned only existing repos, and an empty section would confuse
        // the empty-state test ("no repos → render ContentUnavailableView").
        groups.pruneEmptyRoots()
        discoveredByRoot = groups
        recomputePinned()
        // Clear selection if the previously-selected repo has vanished.
        if let current = selectedRepo, findDiscovered(byPath: current.url.path) == nil {
            selectedRepo = nil
        }
    }

    private func recomputePinned() {
        let pinnedPaths = persistence.settings.pinnedRepos
        let byPath: [String: DiscoveredRepo] = discoveredByRoot.allRepos.reduce(into: [:]) { map, repo in
            map[repo.url.path] = repo
        }
        pinned = pinnedPaths.compactMap { byPath[$0] }
    }

    private func findDiscovered(byPath path: String) -> DiscoveredRepo? {
        discoveredByRoot.allRepos.first { $0.url.path == path }
    }
}

/// Ordered map-like container for discovered repos grouped by root. Keeps
/// root insertion order stable (unlike a plain `[URL: [DiscoveredRepo]]`
/// dictionary) so the sidebar's section ordering is deterministic.
struct OrderedRepoGroups: Equatable {
    private(set) var rootsInOrder: [URL] = []
    private(set) var reposByRoot: [URL: [DiscoveredRepo]] = [:]

    static let empty = OrderedRepoGroups()

    var isEmpty: Bool {
        allRepos.isEmpty
    }

    var allRepos: [DiscoveredRepo] {
        rootsInOrder.flatMap { reposByRoot[$0] ?? [] }
    }

    var ordered: [(root: URL, repos: [DiscoveredRepo])] {
        rootsInOrder.map { ($0, reposByRoot[$0] ?? []) }
    }

    mutating func appendRoot(_ root: URL) {
        guard reposByRoot[root] == nil else { return }
        rootsInOrder.append(root)
        reposByRoot[root] = []
    }

    mutating func append(_ repo: DiscoveredRepo) {
        let key = repo.rootPath.standardizedFileURL
        if reposByRoot[key] == nil {
            rootsInOrder.append(key)
            reposByRoot[key] = [repo]
        } else {
            reposByRoot[key]?.append(repo)
        }
    }

    mutating func pruneEmptyRoots() {
        rootsInOrder.removeAll { (reposByRoot[$0] ?? []).isEmpty }
        for key in Array(reposByRoot.keys) where (reposByRoot[key] ?? []).isEmpty {
            reposByRoot.removeValue(forKey: key)
        }
    }
}
