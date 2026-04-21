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
/// Double-click to switch (VAL-BRANCHOP-004/005): each row runs
/// `BranchOps.switchToLocal` / `switchToRemote` against the focused repo.
/// Double-clicking the current branch is a no-op (we don't spawn a
/// subprocess to ask git to switch to the branch it's already on).
///
/// Fulfills VAL-BRANCH-001, VAL-BRANCH-002, VAL-BRANCH-003, VAL-BRANCH-004,
/// VAL-BRANCHOP-004, VAL-BRANCHOP-005, VAL-BRANCHOP-006.
struct BranchListView: View {
    @Environment(RepoStore.self) private var store
    @Environment(BranchOps.self) private var ops
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
                    BranchRow(branch: branch, onDoubleClick: {
                        handleLocalDoubleClick(branch)
                    })
                }
            }
        }
    }

    private var remoteSections: some View {
        ForEach(model.remoteNames, id: \.self) { remoteName in
            Section {
                DisclosureGroup {
                    ForEach(model.remote[remoteName] ?? [], id: \.fullName) { branch in
                        BranchRow(branch: branch, isRemote: true, onDoubleClick: {
                            handleRemoteDoubleClick(branch)
                        })
                    }
                } label: {
                    Label(remoteName, systemImage: "externaldrive.connected.to.line.below")
                        .font(.body.weight(.medium))
                }
                .accessibilityIdentifier("BranchList.Remote.\(remoteName)")
            }
        }
    }

    // MARK: - Double-click handlers

    /// Double-clicking a local branch switches to it. We skip the subprocess
    /// entirely when the user double-clicks the already-current branch —
    /// `git switch <current>` is a no-op that still forks a Process; skip.
    private func handleLocalDoubleClick(_ branch: Branch) {
        guard let focus = store.focus else { return }
        if branch.isHead { return }
        let name = branch.shortName
        Task { await ops.switchToLocal(name, on: focus) }
    }

    /// Double-clicking a remote branch either (a) switches to an existing
    /// local that already tracks it, or (b) creates a new tracking local
    /// and switches. The "already tracks" probe scans `model.local` for a
    /// branch whose `upstream` string equals `<remote>/<shortBranchName>`.
    private func handleRemoteDoubleClick(_ branch: Branch) {
        guard let focus = store.focus else { return }
        guard let remote = branch.remote else { return }

        // refname:short for a remote branch is e.g. `origin/feature-x`;
        // the "short branch name" we create locally strips the remote prefix.
        let shortBranchName = stripRemotePrefix(branch.shortName, remote: remote)
        let upstreamRef = "\(remote)/\(shortBranchName)"

        // If a local already tracks this remote, delegate to switchToLocal
        // rather than spawning `git switch -c` on an existing name.
        let existingLocal = model.local.first { $0.upstream == upstreamRef }?.shortName

        Task {
            await ops.switchToRemote(
                remote: remote,
                branch: shortBranchName,
                existingLocal: existingLocal,
                on: focus
            )
        }
    }

    /// `origin/feature-x` → `feature-x`. Falls back to the input when the
    /// prefix isn't present (defensive — the parser's shortName for remotes
    /// always carries the remote prefix).
    private func stripRemotePrefix(_ name: String, remote: String) -> String {
        let prefix = "\(remote)/"
        if name.hasPrefix(prefix) {
            return String(name.dropFirst(prefix.count))
        }
        return name
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
