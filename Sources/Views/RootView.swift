import SwiftUI

struct RootView: View {
    @Environment(RepoStore.self) private var repoStore
    @Environment(PersistenceStore.self) private var persistence
    @Environment(AutoFetchController.self) private var autoFetch

    var body: some View {
        NavigationSplitView {
            RepoSidebarView()
        } content: {
            VSplitView {
                BranchPaneView()
                    .frame(minHeight: 160, idealHeight: 320)
                GraphView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("kite.graphPane")
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 360, max: 520)
            .accessibilityIdentifier("kite.content")
        } detail: {
            Text("Diff")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("kite.detail")
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            // VAL-UI-006: toolbar progress indicator. `.status` places it in
            // the center cluster of the macOS unified toolbar on Sequoia+.
            ToolbarItem(placement: .status) {
                ToolbarProgressIndicator()
            }
            // VAL-NET-001 / VAL-UI-002: Fetch action in the trailing primary
            // cluster.
            ToolbarItem(placement: .primaryAction) {
                FetchToolbarButton()
            }
            // VAL-NET-002 / VAL-UI-002: Pull (fast-forward only) beside Fetch.
            ToolbarItem(placement: .primaryAction) {
                PullToolbarButton()
            }
            // VAL-NET-003 / VAL-UI-002: Push (no force) beside Pull.
            ToolbarItem(placement: .primaryAction) {
                PushToolbarButton()
            }
        }
        .overlay(alignment: .bottom) {
            // VAL-UI-004: toast stack anchored at the bottom of the window,
            // overlaid above the three-pane content so it doesn't steal
            // layout from `NavigationSplitView`.
            ToastHostView()
                .allowsHitTesting(true)
        }
        // VAL-NET-006 / VAL-NET-007: auto-fetch is scoped to the focused repo.
        // `.task(id:)` re-runs its closure whenever the focused repo changes,
        // cancelling the task it spawned last time. `retarget` handles the
        // no-focus case (nil-out) and the toggle-off case internally.
        .task(id: repoStore.focus?.repo.id) {
            autoFetch.retarget(to: repoStore.focus)
        }
        // Settings toggle flip picks up via this `.onChange` — `retarget`
        // re-reads `persistence.settings.autoFetchEnabled` and either
        // re-arms or stays off accordingly.
        .onChange(of: persistence.settings.autoFetchEnabled) { _, _ in
            autoFetch.retarget(to: repoStore.focus)
        }
        // Window close: hard-stop the timer so no fetch fires against a
        // repo the user is no longer looking at.
        .onDisappear {
            autoFetch.stop()
        }
    }
}
