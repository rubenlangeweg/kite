import SwiftUI

/// Toolbar button that triggers `NetworkOps.fetch(on:)` against the
/// currently focused repo.
///
/// Disabled when no repo is focused or while a fetch is already in flight
/// — the per-repo `GitQueue` already serialises ops, but the local
/// `isRunning` flag prevents queue build-up from a mashed button.
///
/// Fulfills: VAL-NET-001 (wired to `git fetch --all --prune`),
/// VAL-NET-005 (success toast via ToastCenter), VAL-UI-002 (toolbar button
/// surface for fetch).
struct FetchToolbarButton: View {
    @Environment(RepoStore.self) private var store
    @Environment(NetworkOps.self) private var ops

    @State private var isRunning: Bool = false

    var body: some View {
        Button {
            guard let focus = store.focus else { return }
            isRunning = true
            Task {
                await ops.fetch(on: focus)
                isRunning = false
            }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
        }
        .help("Fetch")
        .disabled(store.focus == nil || isRunning)
        .accessibilityLabel("Fetch")
        .accessibilityIdentifier("Toolbar.Fetch")
    }
}
