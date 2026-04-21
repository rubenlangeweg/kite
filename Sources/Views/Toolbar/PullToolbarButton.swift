import SwiftUI

/// Toolbar button that triggers `NetworkOps.pullFFOnly(on:)` against the
/// currently focused repo.
///
/// Runs `git pull --ff-only` via the shared streaming helper. Non-FF surfaces
/// a sticky "non-fast-forward" toast. Auth / remoteRejected / hookRejected
/// / protectedBranch all surface matching sticky toasts.
///
/// Disabled when no repo is focused or while a pull is already in flight —
/// the per-repo `GitQueue` already serialises ops, but the local `isRunning`
/// flag prevents queue build-up from a mashed button.
///
/// Fulfills: VAL-NET-002 (pull --ff-only + non-FF error toast),
/// VAL-UI-002 (toolbar surface for pull).
struct PullToolbarButton: View {
    @Environment(RepoStore.self) private var store
    @Environment(NetworkOps.self) private var ops

    @State private var isRunning: Bool = false

    var body: some View {
        Button {
            guard let focus = store.focus else { return }
            isRunning = true
            Task {
                _ = await ops.pullFFOnly(on: focus)
                isRunning = false
            }
        } label: {
            Image(systemName: "arrow.down.circle")
        }
        .help("Pull (fast-forward only)")
        .disabled(store.focus == nil || isRunning)
        .accessibilityLabel("Pull")
        .accessibilityIdentifier("Toolbar.Pull")
    }
}
