import Foundation
import Observation

/// App-level selection holder for the diff pane. A single source of truth for
/// "which commit (if any) is currently selected in the graph".
///
/// Lives alongside `RepoStore` and the toast / ops models in the app
/// environment. `DiffPaneRouter` observes `selectedSHA` to decide whether to
/// render `CommitDiffView` (non-nil) or `UncommittedDiffView` (nil), and
/// `GraphView`'s row-tap handler mirrors `GraphModel.select(sha:)` into this
/// property so the two stay in sync while keeping `GraphModel`'s internal
/// state untouched.
///
/// Why a standalone `@Observable` rather than a property on `RepoStore`:
///   - Keeps the router / graph cross-reference narrow — neither side needs
///     to depend on the whole repo-store API to coordinate a SHA string.
///   - Preserves `GraphModel.selectedSHA` so existing GraphModel tests keep
///     passing (no breaking rewrites to those invariants).
///   - Makes it trivial to clear selection on repo swap (single assignment).
///
/// Fulfills: VAL-GRAPH-009 routing contract, VAL-DIFF-003 visibility gate.
@Observable
@MainActor
final class DiffPaneSelection {
    /// Full SHA of the commit the user clicked in the graph. `nil` means
    /// "show the working-copy diff". Any caller (typically `GraphView`)
    /// assigns directly; `DiffPaneRouter` observes.
    var selectedSHA: String?

    init(selectedSHA: String? = nil) {
        self.selectedSHA = selectedSHA
    }
}
