import SwiftUI

/// Pure presentational view for a single unified-diff line (VAL-DIFF-004).
///
/// Renders one of the four `DiffLine` variants with a fixed-width gutter
/// column on the left (`+` / `-` / ` `) and the text content on the right.
/// Coloring:
///   - added   → green text on a faint green wash
///   - removed → red text on a faint red wash
///   - context → primary text, no background
///   - noNewlineMarker → italic, secondary, with the git-style literal
///     "\ No newline at end of file" message
///
/// Monospaced font across every variant, no syntax highlighting (explicitly
/// out of scope for v1 per mission.md §3).
struct DiffLineView: View {
    let line: DiffLine

    var body: some View {
        switch line {
        case let .context(text):
            HStack(spacing: 0) {
                gutter(" ")
                content(text, color: .primary, background: .clear)
            }
        case let .added(text):
            HStack(spacing: 0) {
                gutter("+")
                content(text, color: .green, background: Color.green.opacity(0.08))
            }
        case let .removed(text):
            HStack(spacing: 0) {
                gutter("-")
                content(text, color: .red, background: Color.red.opacity(0.08))
            }
        case .noNewlineMarker:
            HStack(spacing: 0) {
                gutter(" ")
                Text("\\ No newline at end of file")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .italic()
                Spacer(minLength: 0)
            }
        }
    }

    private func gutter(_ char: String) -> some View {
        Text(char)
            .font(.system(size: 11, design: .monospaced))
            .frame(width: 16, alignment: .center)
            .foregroundStyle(.secondary)
    }

    private func content(_ text: String, color: Color, background: Color) -> some View {
        Text(text.isEmpty ? " " : text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .background(background)
    }
}
