import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationSplitView {
            RepoSidebarView()
        } content: {
            VSplitView {
                BranchPaneView()
                    .frame(minHeight: 160, idealHeight: 320)
                Text("Graph (M4)")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("kite.graphPlaceholder")
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
    }
}
