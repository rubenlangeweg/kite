import SwiftUI

/// Middle column's upper pane: local + remote branches for the focused repo.
///
/// Renders three visual regions (each may be absent):
///   1. Detached-HEAD banner (when `HEAD` is detached).
///   2. "Local" section with one `BranchRow` per local branch; the current
///      branch is marked.
///   3. One collapsible `DisclosureGroup` per remote, each containing its
///      branches rendered as muted `BranchRow`s.
///
/// The model reloads in three scenarios:
///   - The focused repo changes (view `.task(id:)`).
///   - FSWatcher fires on `.git/` (observed via `focus.lastChangeAt`).
///   - The user pulls to refresh (macOS list `.refreshable`).
///
/// Fulfills VAL-BRANCH-001, VAL-BRANCH-002, VAL-BRANCH-003, VAL-BRANCH-004.
struct BranchListView: View {
    @Environment(RepoStore.self) private var store
    @State private var model = BranchListModel()

    var body: some View {
        Group {
            if let focus = store.focus {
                loadedBody(focus: focus)
            } else {
                ContentUnavailableView(
                    "Select a repository",
                    systemImage: "sidebar.left",
                    description: Text("Choose a repo from the sidebar to see its branches.")
                )
                .accessibilityIdentifier("BranchList.EmptyState")
            }
        }
    }

    private func loadedBody(focus: RepoFocus) -> some View {
        List {
            detachedHeadSection
            localSection
            remoteSections
            errorSection
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("BranchList.List")
        .overlay(alignment: .top) {
            if model.isLoading, model.local.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 12)
            }
        }
        .refreshable {
            await model.reload(for: focus)
        }
        .task(id: focus.repo.id) {
            await model.reload(for: focus)
        }
        .onChange(of: focus.lastChangeAt) { _, _ in
            Task { await model.reload(for: focus) }
        }
    }

    @ViewBuilder
    private var detachedHeadSection: some View {
        if let detached = model.detachedHead {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("HEAD detached at \(detached.shortSHA)")
                            .font(.body.weight(.semibold))
                        Text("Create a branch to keep commits reachable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .accessibilityIdentifier("BranchList.DetachedHeadBanner")
            }
        }
    }

    private var localSection: some View {
        Section("Local") {
            if model.local.isEmpty, !model.isLoading {
                Text("No local branches")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.local, id: \.fullName) { branch in
                    BranchRow(branch: branch)
                }
            }
        }
    }

    private var remoteSections: some View {
        ForEach(model.remoteNames, id: \.self) { remoteName in
            Section {
                DisclosureGroup {
                    ForEach(model.remote[remoteName] ?? [], id: \.fullName) { branch in
                        BranchRow(branch: branch, isRemote: true)
                    }
                } label: {
                    Label(remoteName, systemImage: "externaldrive.connected.to.line.below")
                        .font(.body.weight(.medium))
                }
                .accessibilityIdentifier("BranchList.Remote.\(remoteName)")
            }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error = model.lastError {
            Section {
                Label(error, systemImage: "exclamationmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("BranchList.Error")
            }
        }
    }
}
