import SwiftUI

struct RootView: View {
    @State private var contentSelection: String?

    var body: some View {
        NavigationSplitView {
            RepoSidebarView()
        } content: {
            List(selection: $contentSelection) {
                Text("Branches and graph")
                    .foregroundStyle(.secondary)
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 360)
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
