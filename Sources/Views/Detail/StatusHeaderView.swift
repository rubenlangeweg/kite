import SwiftUI

/// Compact one-line status header shown above the branch list.
///
/// Renders `<branch>  •  <clean | pills>  <↑N ↓M>` with:
///   - SF-Symbol branch marker + branch name (or "HEAD detached at <sha>").
///   - Separator dot.
///   - Clean working tree → green check + "Clean".
///   - Dirty working tree → pill cluster: only non-zero groups are shown
///     (`X staged`, `Y modified`, `Z untracked`), each with a tinted bg.
///   - Upstream divergence → trailing monospaced `↑N ↓M`.
///
/// Owns its own `StatusHeaderModel`; observes the ambient `RepoStore` for
/// focus changes and reloads on `focus.lastChangeAt` (FSWatcher tick), which
/// closes the end-to-end refresh loop for VAL-REPO-010.
///
/// Fulfills: VAL-BRANCH-005, VAL-REPO-010.
struct StatusHeaderView: View {
    @Environment(RepoStore.self) private var store
    @State private var model = StatusHeaderModel()

    var body: some View {
        Group {
            if let focus = store.focus {
                StatusHeaderContent(
                    summary: model.summary,
                    isLoading: model.isLoading,
                    lastError: model.lastError
                )
                .task(id: focus.repo.id) {
                    await model.reload(for: focus)
                }
                .onChange(of: focus.lastChangeAt) { _, _ in
                    Task { await model.reload(for: focus) }
                }
            } else {
                StatusHeaderContent.placeholder
            }
        }
    }
}

/// Pure presentational subview — given a `StatusSummary?` + auxiliary state,
/// it renders the exact header the `StatusHeaderView` shows. Split out from
/// the stateful wrapper so snapshot tests can drive every visual branch
/// without spinning up a fixture repo + `RepoStore`.
struct StatusHeaderContent: View {
    let summary: StatusSummary?
    let isLoading: Bool
    let lastError: String?

    init(summary: StatusSummary?, isLoading: Bool = false, lastError: String? = nil) {
        self.summary = summary
        self.isLoading = isLoading
        self.lastError = lastError
    }

    var body: some View {
        HStack(spacing: 8) {
            branchLabel
            if summary != nil || lastError != nil {
                separator
                statusCluster
            }
            Spacer(minLength: 4)
            aheadBehind
        }
        .font(.system(size: 12, weight: .medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityIdentifier("StatusHeader")
    }

    /// "No repository focused" placeholder used when the store has no focus.
    @MainActor
    static var placeholder: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.secondary)
            Text("No repository")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12, weight: .medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityIdentifier("StatusHeader")
    }

    // MARK: - Branch label

    private var branchLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.secondary)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(branchText)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityIdentifier("StatusHeader.Branch")
        }
    }

    private var branchText: String {
        if let summary {
            if let branch = summary.branch { return branch }
            if let detached = summary.detachedAt { return "HEAD detached at \(detached)" }
            return "(no branch)"
        }
        return isLoading ? "…" : "(unknown)"
    }

    // MARK: - Separator + status cluster

    private var separator: some View {
        Text("•")
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var statusCluster: some View {
        if let summary {
            if summary.isClean {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .imageScale(.small)
                        .accessibilityHidden(true)
                    Text("Clean")
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("StatusHeader.Clean")
            } else {
                HStack(spacing: 6) {
                    if summary.staged > 0 {
                        countPill(count: summary.staged, label: "staged", tint: .green)
                            .accessibilityIdentifier("StatusHeader.Staged")
                    }
                    if summary.modified > 0 {
                        countPill(count: summary.modified, label: "modified", tint: .orange)
                            .accessibilityIdentifier("StatusHeader.Modified")
                    }
                    if summary.untracked > 0 {
                        countPill(count: summary.untracked, label: "untracked", tint: .blue)
                            .accessibilityIdentifier("StatusHeader.Untracked")
                    }
                }
            }
        } else if let error = lastError {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .imageScale(.small)
                Text(error)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .accessibilityIdentifier("StatusHeader.Error")
        }
    }

    private func countPill(count: Int, label: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Text("\(count)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            Text(label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tint.opacity(0.18), in: Capsule())
    }

    // MARK: - Ahead/behind indicator

    @ViewBuilder
    private var aheadBehind: some View {
        if let summary, summary.upstream != nil,
           summary.ahead > 0 || summary.behind > 0
        {
            HStack(spacing: 6) {
                if summary.ahead > 0 {
                    Label("\(summary.ahead)", systemImage: "arrow.up")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("StatusHeader.Ahead")
                }
                if summary.behind > 0 {
                    Label("\(summary.behind)", systemImage: "arrow.down")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("StatusHeader.Behind")
                }
            }
        }
    }
}
