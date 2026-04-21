import SwiftUI

/// Toolbar button that presents `NewBranchSheet` against the currently
/// focused repo. Disabled when no repo is focused.
///
/// Wires the sheet's `onCreate` to `BranchOps.createBranch(_:on:)`. On
/// either success or failure the sheet is dismissed — the outcome surfaces
/// via `ToastCenter` so the sheet doesn't have to double-render errors.
///
/// ⌘⇧N (M8-commands-and-menu) also routes to this button's sheet: the
/// menu bumps `AppCommands.newBranchRequest` and the `.onChange` observer
/// below opens the sheet just like a click. Keeps sheet ownership in one
/// place while letting multiple surfaces invoke it.
///
/// Fulfills: VAL-BRANCHOP-001 (toolbar + menu surface that opens the sheet),
/// VAL-UI-002 (toolbar button for new-branch), VAL-UI-003 (⌘⇧N menu entry
/// opens the same sheet).
struct NewBranchButton: View {
    @Environment(RepoStore.self) private var store
    @Environment(BranchOps.self) private var ops
    @Environment(AppCommands.self) private var appCommands

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
        // ⌘⇧N from the Repository menu bumps `newBranchRequest`. A nil →
        // non-nil transition opens the sheet; any subsequent bump (new
        // UUID) also opens it even if the sheet was dismissed in between.
        .onChange(of: appCommands.newBranchRequest) { _, newValue in
            guard newValue != nil, store.focus != nil else { return }
            showSheet = true
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
