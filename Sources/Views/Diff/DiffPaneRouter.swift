import SwiftUI

/// Right-column router that picks the diff view based on `DiffPaneSelection`:
///
///   - `selection.selectedSHA != nil` → `CommitDiffView(sha:)` (the user
///     clicked a commit in the graph; show `git show <sha>`).
///   - `selection.selectedSHA == nil` → `UncommittedDiffView()` (default;
///     show the working-copy diff).
///
/// When the focused repo changes (`RepoStore.focus.repo.id`), we clear the
/// selection automatically so the router falls back to the working-copy diff
/// for the newly focused repo — carrying a stale SHA across repo switches
/// would either show the wrong commit or (more likely) surface a "bad
/// revision" error.
///
/// Fulfills: VAL-DIFF-003 visibility gate, VAL-GRAPH-009 cross-milestone glue.
struct DiffPaneRouter: View {
    @Environment(DiffPaneSelection.self) private var selection
    @Environment(RepoStore.self) private var store

    var body: some View {
        Group {
            if let sha = selection.selectedSHA {
                CommitDiffView(sha: sha)
            } else {
                UncommittedDiffView()
            }
        }
        .onChange(of: store.focus?.repo.id) { _, _ in
            // Repo swap: clear any lingering commit selection so the pane
            // falls back to the working-copy diff of the new repo. The
            // previous repo's SHA would be meaningless here.
            selection.selectedSHA = nil
        }
        .accessibilityIdentifier("DiffPaneRouter")
    }
}
