import SwiftUI

/// Pure presentational view for a single commit's metadata — rendered above
/// the file diffs in `CommitDiffView`.
///
/// Layout:
///
/// ```
/// ┌─────────────────────────────────────────────────┐
/// │  subject (bold)                        <shortSHA> │
/// │  body (optional, multiline)                       │
/// │  author <email> • date                            │
/// │  [pill] [pill] [pill]   (if any refs)             │
/// └─────────────────────────────────────────────────┘
/// ```
///
/// Strictly presentational — no git, no environment. Snapshot tests drive
/// this directly with hand-built `CommitHeader` values.
struct CommitHeaderView: View {
    let header: CommitHeader

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(header.subject)
                    .font(.title3)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(header.shortSHA)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if !header.body.isEmpty {
                Text(header.body)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 6) {
                Text("\(header.authorName) <\(header.authorEmail)>")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("•")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(header.authoredAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            if !header.refs.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(header.refs.enumerated()), id: \.offset) { _, ref in
                        RefPill(kind: ref)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("CommitHeader")
    }
}
