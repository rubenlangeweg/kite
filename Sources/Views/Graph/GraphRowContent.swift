import SwiftUI

/// Pure inner view composing the whole graph row: graph column on the left,
/// then pills, subject, author, and a live-updating relative-age label on
/// the right.
///
/// Layout (library §5 row content):
///
/// ```
/// [ graph canvas ] [ pills ] [ subject (flex, tail-truncated) ] [ author ] [ age ]
/// ```
///
/// Per AGENTS.md "Established patterns" this is the STATEFUL-OUTER / PURE-INNER
/// contract: `GraphRowContent` takes fully-resolved value types and never
/// touches an `@Environment`, a model, or a fixture. Snapshot tests drive it
/// directly. The stateful outer scroll container lives in
/// `M4-graph-scroll-container`.
///
/// Pill policy per VAL-GRAPH-007:
///   - Tags are filtered (v1 is branches-only).
///   - At most 3 pills render; the 4th+ collapse into a `+N` grey label.
///
/// Age is wrapped in `TimelineView(.periodic(from: .now, by: 60))` so a commit
/// labelled `1m` rolls to `2m` without the row having to own a timer — library
/// §5 "drive it off a shared TimelineView".
///
/// Fulfills: VAL-GRAPH-001 (a row CAN render with refs — the 200-commit count
/// enforcement lives in the scroll container that wraps this view),
/// VAL-GRAPH-007 (branch pills + `+N` overflow).
struct GraphRowContent: View {
    let row: LayoutRow
    let laneCount: Int
    let isSelected: Bool

    /// Max pills rendered inline; the rest collapse into `+N`.
    private static let pillOverflowThreshold = 3

    init(row: LayoutRow, laneCount: Int, isSelected: Bool = false) {
        self.row = row
        self.laneCount = laneCount
        self.isSelected = isSelected
    }

    var body: some View {
        HStack(spacing: 8) {
            GraphCell(
                row: row,
                laneCount: laneCount,
                isSelected: isSelected,
                hasRef: !visibleRefs.isEmpty
            )

            pillCluster

            Text(row.commit.subject)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.commit.authorName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 140, alignment: .leading)

            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(RelativeAgeFormatter.format(from: row.commit.authoredAt, now: context.date))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 64, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: GraphCell.rowHeight)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
    }

    // MARK: - Pill cluster

    @ViewBuilder
    private var pillCluster: some View {
        if visibleRefs.isEmpty, overflowCount == 0 {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                ForEach(Array(pillsToShow.enumerated()), id: \.offset) { _, ref in
                    RefPill(kind: ref)
                }
                if overflowCount > 0 {
                    Text("+\(overflowCount)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Branch refs filtered of tags — tags are never rendered in v1 per mission
    /// §3. `GraphRowRefs.enrich` already drops them but keep this filter as a
    /// belt-and-braces guard so hand-built rows in tests and previews can't
    /// surface a tag pill.
    private var visibleRefs: [RefKind] {
        row.refs.filter { ref in
            if case .tag = ref { return false }
            return true
        }
    }

    private var pillsToShow: [RefKind] {
        Array(visibleRefs.prefix(Self.pillOverflowThreshold))
    }

    private var overflowCount: Int {
        max(0, visibleRefs.count - Self.pillOverflowThreshold)
    }
}
