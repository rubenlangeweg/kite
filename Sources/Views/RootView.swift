import SwiftUI

struct RootView: View {
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
        }
        .overlay(alignment: .bottom) {
            // VAL-UI-004: toast stack anchored at the bottom of the window,
            // overlaid above the three-pane content so it doesn't steal
            // layout from `NavigationSplitView`.
            ToastHostView()
                .allowsHitTesting(true)
        }
    }
}
