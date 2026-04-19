import SwiftUI

struct RootView: View {
    @State private var sidebarSelection: String?
    @State private var contentSelection: String?

    var body: some View {
        NavigationSplitView {
            List(selection: $sidebarSelection) {
                Text("Repos")
                    .foregroundStyle(.secondary)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
            .accessibilityIdentifier("kite.sidebar")
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
        .navigationTitle("Kite")
    }
}

#Preview {
    RootView()
}
