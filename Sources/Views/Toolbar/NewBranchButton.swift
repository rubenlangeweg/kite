import SwiftUI

/// Toolbar button that presents `NewBranchSheet` against the currently
/// focused repo. Disabled when no repo is focused.
///
/// Wires the sheet's `onCreate` to `BranchOps.createBranch(_:on:)`. On
/// either success or failure the sheet is dismissed — the outcome surfaces
/// via `ToastCenter` so the sheet doesn't have to double-render errors.
///
/// The ⌘⇧N keyboard shortcut is wired in M8-commands-and-menu (spec §4);
/// for M6-create-branch this button + the App menu entry (future) are the
/// only surfaces.
///
/// Fulfills: VAL-BRANCHOP-001 (toolbar surface that opens the sheet),
/// VAL-UI-002 (toolbar button for new-branch).
struct NewBranchButton: View {
    @Environment(RepoStore.self) private var store
    @Environment(BranchOps.self) private var ops

    @State private var showSheet: Bool = false

    var body: some View {
        Button {
            guard store.focus != nil else { return }
            showSheet = true
        } label: {
            Image(systemName: "plus.rectangle.on.folder")
        }
        .help("New branch")
        .disabled(store.focus == nil)
        .accessibilityLabel("New branch")
        .accessibilityIdentifier("Toolbar.NewBranch")
        .sheet(isPresented: $showSheet) {
            NewBranchSheet(
                currentBranch: currentBranchName,
                onCreate: { name in
                    if let focus = store.focus {
                        _ = await ops.createBranch(name, on: focus)
                    }
                    showSheet = false
                },
                onCancel: {
                    showSheet = false
                }
            )
        }
    }

    /// Decorative hint for the sheet's "forks from" label. Best-effort — a
    /// reliable "current branch" surface lives in `BranchListModel` which
    /// this view doesn't inherit. Returning `nil` is acceptable; the sheet
    /// renders a generic prompt in that case.
    private var currentBranchName: String? {
        nil
    }
}
