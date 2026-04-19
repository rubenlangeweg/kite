import SwiftUI

/// Scrollable container view composing `GraphRowContent` rows into a
/// `List` for the focused repo's commit DAG (VAL-GRAPH-009/010/011).
///
/// Stateful outer + pure inner split per AGENTS.md "Established patterns":
///   - `GraphView` (this file) owns the `@Observable` `GraphModel`, observes
///     the ambient `RepoStore`, reacts to focus swaps and FSWatcher ticks.
///   - `GraphViewContent` (below, file-scope) is a pure struct-of-values view
///     that snapshot tests drive directly — no environment, no model, no git.
///
/// Scroll-preservation (VAL-GRAPH-010):
/// SwiftUI's `List` diffs rows by `Identifiable.id` — because every
/// `LayoutRow.id == commit.sha` is stable across refreshes, an FSEvents-driven
/// reload that leaves most rows in place keeps the user's scroll offset pinned
/// to the row beneath the cursor. No manual `ScrollViewReader` dance needed.
///
/// Selection (VAL-GRAPH-009):
/// Row tap calls `model.select(sha:)`. The future M7 diff pane observes
/// `model.selectedSHA` to run `git show <sha>` in the right split.
///
/// Fulfills: VAL-GRAPH-009, VAL-GRAPH-010, VAL-GRAPH-011.
struct GraphView: View {
    @Environment(RepoStore.self) private var store
    @State private var model = GraphModel()

    var body: some View {
        Group {
            if let focus = store.focus {
                loadedBody(focus: focus)
            } else {
                emptyState
            }
        }
    }

    private func loadedBody(focus: RepoFocus) -> some View {
        GraphViewContent(
            rows: model.rows,
            isShallowRepo: model.isShallowRepo,
            commitLimitHit: model.commitLimitHit,
            isLoading: model.isLoading,
            lastError: model.lastError,
            selectedSHA: model.selectedSHA,
            onSelect: { sha in model.select(sha: sha) }
        )
        .task(id: focus.repo.id) {
            await model.reload(for: focus)
        }
        .onChange(of: focus.lastChangeAt) { _, _ in
            Task { await model.reload(for: focus) }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Select a repository",
            systemImage: "point.3.connected.trianglepath.dotted",
            description: Text("Choose a repo from the sidebar to see its commit graph.")
        )
        .accessibilityIdentifier("GraphView.EmptyState")
    }
}

/// Pure presentational inner view — given a slice of `GraphModel`'s observable
/// state, renders the scrollable graph. Snapshot tests drive this directly
/// with hand-built `[LayoutRow]` so they don't need a fixture repo or the
/// `RepoStore` environment.
///
/// Lane width is computed from the max column across visible rows so the
/// dedicated per-row `GraphCell` can align columns vertically — all rows in a
/// refresh share the same `laneCount`.
struct GraphViewContent: View {
    let rows: [LayoutRow]
    let isShallowRepo: Bool
    let commitLimitHit: Bool
    let isLoading: Bool
    let lastError: String?
    let selectedSHA: String?
    let onSelect: (String?) -> Void

    init(
        rows: [LayoutRow],
        isShallowRepo: Bool = false,
        commitLimitHit: Bool = false,
        isLoading: Bool = false,
        lastError: String? = nil,
        selectedSHA: String? = nil,
        onSelect: @escaping (String?) -> Void = { _ in }
    ) {
        self.rows = rows
        self.isShallowRepo = isShallowRepo
        self.commitLimitHit = commitLimitHit
        self.isLoading = isLoading
        self.lastError = lastError
        self.selectedSHA = selectedSHA
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(spacing: 0) {
            if isShallowRepo {
                ShallowCloneBanner()
            }
            if let error = lastError, rows.isEmpty {
                errorState(error)
            } else if rows.isEmpty, !isLoading {
                emptyGraphState
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("GraphView")
    }

    private var list: some View {
        List {
            ForEach(rows) { row in
                GraphRowContent(
                    row: row,
                    laneCount: laneCount,
                    isSelected: row.commit.sha == selectedSHA
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
                .contentShape(Rectangle())
                .accessibilityIdentifier("GraphRow.\(row.commit.sha)")
                .onTapGesture { onSelect(row.commit.sha) }
            }
            if commitLimitHit {
                CommitLimitFooter()
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("GraphView.List")
    }

    private var emptyGraphState: some View {
        ContentUnavailableView(
            "No commits",
            systemImage: "point.3.connected.trianglepath.dotted",
            description: Text("This repository has no commits yet.")
        )
        .accessibilityIdentifier("GraphView.NoCommits")
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 12))
                .accessibilityIdentifier("GraphView.Error")
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Column count used to size every row's `GraphCell`. At least 1 so the
    /// canvas isn't zero-width for a single-lane graph.
    private var laneCount: Int {
        (rows.map(\.column).max() ?? 0) + 1
    }
}

/// Top-of-graph banner shown when the focused repo is a shallow clone.
/// Fulfills VAL-GRAPH-011.
struct ShallowCloneBanner: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text("Shallow clone — history truncated.")
                .font(.system(size: 11))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .accessibilityIdentifier("GraphView.ShallowBanner")
    }
}

/// Bottom footer row shown when the log hit the 200-commit cap — older
/// commits exist but aren't visible. Fulfills the truncation marker half of
/// VAL-GRAPH-001.
struct CommitLimitFooter: View {
    var body: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text("200-commit limit — older history not shown.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("GraphView.CommitLimitFooter")
    }
}
