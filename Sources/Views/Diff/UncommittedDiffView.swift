import SwiftUI

/// Right-pane container showing the read-only working-copy diff
/// (VAL-DIFF-001/002/004/005/006/007).
///
/// Design notes per AGENTS.md "Established patterns":
///
///   - Stateful outer view owns `@State private var model = UncommittedDiffModel()`
///     and observes `store.focus.lastChangeAt` for FSEvents-driven reloads.
///   - `LazyVStack` (inside a `ScrollView`) is what satisfies VAL-DIFF-006:
///     rows render only as they scroll into view, keeping memory bounded even
///     for 10k-line diffs.
///   - Strict read-only: no `Button` in this view tree mutates git state.
///     Future stage/discard/revert would need its own feature, not a silent
///     addition to this surface. (VAL-DIFF-007)
///   - On clean trees we show a `ContentUnavailableView` with the
///     `checkmark.seal` SF Symbol. (VAL-DIFF-002)
///   - Error state is surfaced inline above the content with a small banner —
///     non-blocking, not modal, since the user can still scroll any prior
///     content that's already rendered (we clear on error but the banner
///     itself stays usable).
struct UncommittedDiffView: View {
    @Environment(RepoStore.self) private var store
    @State private var model = UncommittedDiffModel()

    var body: some View {
        content
            // `.task(id:)` cancels and re-spawns whenever the focused repo
            // changes. `model.reload` in turn cancels its own prior Task, so
            // a rapid focus swap never leaves two git diffs in flight.
            .task(id: store.focus?.repo.id) {
                if let focus = store.focus {
                    await model.reload(for: focus)
                } else {
                    model.clear()
                }
            }
            // FSEvents-driven auto-refresh (VAL-REPO-010 for working-copy
            // edits). `onChange` fires whenever `RepoFocus.lastChangeAt`
            // bumps; the model's cancel-prior-Task discipline dedupes
            // storms.
            .onChange(of: store.focus?.lastChangeAt) { _, _ in
                if let focus = store.focus {
                    Task { await model.reload(for: focus) }
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
                    if isEmpty {
                        emptyState
                    } else {
                        if !model.staged.isEmpty {
                            sectionHeader("Staged changes")
                            ForEach(Array(model.staged.enumerated()), id: \.offset) { _, diff in
                                FileDiffView(diff: diff)
                            }
                        }
                        if !model.unstaged.isEmpty {
                            sectionHeader("Unstaged changes")
                            ForEach(Array(model.unstaged.enumerated()), id: \.offset) { _, diff in
                                FileDiffView(diff: diff)
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("UncommittedDiff")
        }
    }

    private var isEmpty: Bool {
        model.unstaged.isEmpty &&
            model.staged.isEmpty &&
            !model.isLoading &&
            model.lastError == nil
    }

    // MARK: - States

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No uncommitted changes", systemImage: "checkmark.seal")
        } description: {
            Text("Working tree is clean.")
        }
        .accessibilityIdentifier("UncommittedDiff.Empty")
    }

    private var noFocusState: some View {
        ContentUnavailableView {
            Label("No repository selected", systemImage: "sidebar.left")
        } description: {
            Text("Pick a repository from the sidebar to see its working-copy diff.")
        }
        .accessibilityIdentifier("UncommittedDiff.NoFocus")
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .accessibilityIdentifier("UncommittedDiff.Section.\(text)")
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
        .accessibilityIdentifier("UncommittedDiff.Error")
    }
}
