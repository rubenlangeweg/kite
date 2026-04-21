import SwiftUI

/// Right-pane container showing the selected commit's diff
/// (VAL-DIFF-003/006, VAL-GRAPH-009).
///
/// Stateful outer / pure inner split per AGENTS.md:
///   - `CommitDiffView` (this file) owns the `@Observable` `CommitDiffModel`
///     and observes the ambient `RepoStore` focus.
///   - `CommitHeaderView` + `FileDiffView` are pure presentational children
///     driven by fully-resolved value types — snapshot tests target them
///     directly.
///
/// Virtualization for large commits (VAL-DIFF-006): the whole commit is
/// wrapped in a `ScrollView` + `LazyVStack`; `FileDiffView` itself materializes
/// its hunks eagerly, but the N-file outer list is lazy so a 100-file
/// refactor doesn't pay for everything off-screen. Combined with the M1-fix-
/// git-run-drain pipe drain, a 10k-line `git show` is a must-work case.
///
/// `.task(id: sha)` is the entry point: SwiftUI re-invokes the closure
/// whenever `sha` changes, which happens any time the user clicks a different
/// commit in the graph. `CommitDiffModel.load(sha:)`'s own de-dup guard
/// handles the SwiftUI-issued same-SHA re-invocation we occasionally see on
/// hierarchy reshuffles.
struct CommitDiffView: View {
    let sha: String

    @Environment(RepoStore.self) private var store
    @State private var model = CommitDiffModel()

    var body: some View {
        content
            .task(id: sha) {
                if let focus = store.focus {
                    await model.load(sha: sha, for: focus)
                } else {
                    model.clear()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if store.focus == nil {
            noFocusState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let error = model.lastError {
                        errorBanner(error)
                    }
                    if let header = model.header {
                        CommitHeaderView(header: header)
                    } else if model.isLoading {
                        loadingRow
                    }
                    ForEach(Array(model.files.enumerated()), id: \.offset) { _, diff in
                        FileDiffView(diff: diff)
                    }
                    if model.header != nil, model.files.isEmpty, !model.isLoading, model.lastError == nil {
                        emptyDiffState
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("CommitDiff")
        }
    }

    // MARK: - States

    private var loadingRow: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text("Loading commit…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("CommitDiff.Loading")
    }

    private var emptyDiffState: some View {
        Text("This commit introduces no file changes.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .italic()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .accessibilityIdentifier("CommitDiff.EmptyDiff")
    }

    private var noFocusState: some View {
        ContentUnavailableView {
            Label("No repository selected", systemImage: "sidebar.left")
        } description: {
            Text("Pick a repository from the sidebar to see a commit's diff.")
        }
        .accessibilityIdentifier("CommitDiff.NoFocus")
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 11))
                .lineLimit(3)
            Spacer()
        }
        .padding(8)
        .background(Color.red.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("CommitDiff.Error")
    }
}
