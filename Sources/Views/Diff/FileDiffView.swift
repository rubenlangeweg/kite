import SwiftUI

/// Pure presentational view for a single `FileDiff` — renders a header row
/// (icon + file path) on top of the file's hunks (each prefaced by a hunk
/// header `@@ -X,Y +A,B @@`), or a placeholder for binary files
/// (VAL-DIFF-005).
///
/// Icon convention:
///   - `plus.circle`  — new file (`oldPath == nil`)
///   - `minus.circle` — deleted file (`newPath == nil`)
///   - `doc`          — regular modification / rename
///
/// Strictly presentational: no buttons, no context menus, no actions. The
/// read-only invariance (VAL-DIFF-007) is enforced by construction — nothing
/// here mutates git state.
struct FileDiffView: View {
    let diff: FileDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            body(of: diff)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("FileDiff.\(headerText)")
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
            Text(headerText)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func body(of diff: FileDiff) -> some View {
        if diff.isBinary {
            Text("Binary file — not displayed")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .italic()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .accessibilityIdentifier("FileDiff.Binary")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diff.hunks.enumerated()), id: \.offset) { _, hunk in
                    hunkHeader(hunk)
                    ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                        DiffLineView(line: line)
                    }
                }
            }
        }
    }

    private func hunkHeader(_ hunk: Hunk) -> some View {
        Text("@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
    }

    // MARK: - Header metadata

    private var iconName: String {
        if diff.oldPath == nil { return "plus.circle" }
        if diff.newPath == nil { return "minus.circle" }
        return "doc"
    }

    private var headerText: String {
        diff.newPath ?? diff.oldPath ?? "(unknown)"
    }
}
