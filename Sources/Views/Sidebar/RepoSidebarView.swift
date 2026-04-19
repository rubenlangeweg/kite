import AppKit
import SwiftUI

/// Leftmost column of the main `NavigationSplitView`: repo list grouped by
/// root, with a Pinned section on top when populated. Empty state delegates
/// to `EmptyRepoList`.
///
/// The view binds its selection through the shared `RepoSidebarModel`.
/// Selection changes write through to persistence so `restoreLastSelection()`
/// can replay them on relaunch (VAL-REPO-008).
struct RepoSidebarView: View {
    @Environment(RepoSidebarModel.self) private var model
    @Environment(PersistenceStore.self) private var persistence

    var body: some View {
        content
            .navigationTitle("Kite")
            .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 400)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Rescan roots")
                    .accessibilityIdentifier("RepoSidebar.RefreshButton")
                    .disabled(model.isScanning)
                }
            }
            .task {
                await model.refresh()
                await model.restoreLastSelection()
            }
    }

    @ViewBuilder
    private var content: some View {
        if !model.hasAnyRepos, !model.isScanning {
            EmptyRepoList()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            repoList
        }
    }

    private var repoList: some View {
        List(selection: selectionBinding) {
            if !model.pinned.isEmpty {
                Section {
                    ForEach(model.pinned) { repo in
                        RepoRow(repo: repo)
                            .tag(repo as DiscoveredRepo?)
                            .contextMenu {
                                contextMenuItems(for: repo, isPinned: true)
                            }
                    }
                } header: {
                    Label("Pinned", systemImage: "pin.fill")
                        .accessibilityIdentifier("RepoSidebar.PinnedSection")
                }
            }

            ForEach(model.rootSections, id: \.root) { section in
                Section {
                    ForEach(section.repos) { repo in
                        RepoRow(repo: repo)
                            .tag(repo as DiscoveredRepo?)
                            .contextMenu {
                                contextMenuItems(for: repo, isPinned: isPinned(repo))
                            }
                    }
                } header: {
                    Text(section.root.lastPathComponent)
                        .help(section.root.path)
                        .accessibilityIdentifier("RepoSidebar.RootSection.\(section.root.lastPathComponent)")
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("RepoSidebar.List")
    }

    private var selectionBinding: Binding<DiscoveredRepo?> {
        Binding(
            get: { model.selectedRepo },
            set: { model.select($0) }
        )
    }

    @ViewBuilder
    private func contextMenuItems(for repo: DiscoveredRepo, isPinned: Bool) -> some View {
        if isPinned {
            Button("Unpin") { model.unpin(repo) }
        } else {
            Button("Pin") { model.pin(repo) }
        }
        Divider()
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([repo.url])
        }
        Button("Copy path") {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(repo.url.path, forType: .string)
        }
    }

    private func isPinned(_ repo: DiscoveredRepo) -> Bool {
        persistence.settings.pinnedRepos.contains(repo.url.path)
    }
}
