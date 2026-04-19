import Foundation
import Observation

/// App-level owner of the currently focused `RepoFocus`.
///
/// Lives alongside `PersistenceStore` and `RepoSidebarModel` in the app
/// environment. On every focus swap the previous `RepoFocus` is torn down
/// (explicit `shutdown()` before releasing the reference so the cleanup runs
/// on the main actor, which is where ARC-driven deinit would otherwise fall
/// off of) and a fresh `RepoFocus` is built for the new repo.
///
/// The last-opened path is mirrored to persistence so relaunches can restore
/// the previous selection (VAL-REPO-008). `RepoSidebarModel.select(_:)` also
/// writes to persistence — we write here too so the focus-swap path is
/// self-sufficient when driven from code paths that don't go through the
/// sidebar (tests, future auto-restore, etc.).
///
/// Fulfills: VAL-NET-009 and VAL-NET-010 alongside `GitQueue` + `RepoFocus`.
@Observable
@MainActor
final class RepoStore {
    @ObservationIgnored
    private let persistence: PersistenceStore

    /// The currently focused repo's coordinator, or `nil` when nothing is
    /// focused (empty state, or just after a focus(on: nil)).
    private(set) var focus: RepoFocus?

    init(persistence: PersistenceStore) {
        self.persistence = persistence
    }

    /// Switch focus to `repo`. Tears down the previous `RepoFocus` (explicit
    /// `shutdown()` + release) before instantiating the new one, and writes
    /// the persisted last-opened path.
    func focus(on repo: DiscoveredRepo?) {
        focus?.shutdown()
        focus = nil

        guard let repo else {
            persistence.setLastOpenedRepo(nil)
            return
        }

        focus = RepoFocus(repo: repo)
        persistence.setLastOpenedRepo(repo.url.path)
    }
}
