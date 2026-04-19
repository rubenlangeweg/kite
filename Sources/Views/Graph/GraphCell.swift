import SwiftUI

/// Pure inner view that renders the graph column (dots + edges) for a single
/// `LayoutRow` inside a `SwiftUI.Canvas`. The outer scroll container
/// (M4-graph-scroll-container) assembles these into a `List` with matching
/// `laneCount` so every row has identical width for column alignment.
///
/// Establshed pattern: pure inner view — no `@Environment`, no models, no
/// git. Value-types in, pixels out. Snapshot tests exercise this view
/// directly with hand-built `LayoutRow` fixtures.
///
/// Edge shape is a 3-segment straight/diagonal path (no bezier) per decision
/// #18 in `mission.md` and library §2: a short vertical stub entering from
/// the top edge, a diagonal to `(toX, midY)`, and a symmetric stub leaving
/// to the bottom edge for outgoing edges.
///
/// Fulfills VAL-GRAPH-004 (stable colors — via `LanePalette`), VAL-GRAPH-005
/// (`main` blue — via `LanePalette`), and sets up VAL-GRAPH-008's 60fps goal
/// architecturally (per-row Canvas in a virtualized List, bounded segment
/// count per row).
struct GraphCell: View {
    let row: LayoutRow
    /// Number of lanes visible in the graph (max column across the full
    /// visible range). Callers pass this so every row renders at identical
    /// width and columns align vertically across the list.
    let laneCount: Int
    /// Whether this row corresponds to the currently-selected commit; draws
    /// an accent ring around the dot.
    var isSelected: Bool = false
    /// Whether a ref (branch or HEAD) points at this commit — used to draw a
    /// bolder dot.
    var hasRef: Bool = false

    static let laneWidth: CGFloat = 14
    static let rowHeight: CGFloat = 22
    static let dotRadius: CGFloat = 4
    static let lineWidth: CGFloat = 1.5

    /// Tangent stub height: vertical distance from the row edge the edge
    /// runs before / after the diagonal segment. Kept small so the diagonal
    /// actually reaches the dot's midline cleanly.
    private static let stubHeight: CGFloat = 4

    var body: some View {
        Canvas { context, size in
            draw(in: context, size: size)
        }
        .frame(width: CGFloat(max(laneCount, 1)) * Self.laneWidth, height: Self.rowHeight)
    }

    // MARK: - Drawing

    private func draw(in context: GraphicsContext, size: CGSize) {
        let midY = size.height / 2

        for edge in row.inEdges {
            drawInEdge(edge, midY: midY, in: context)
        }
        for edge in row.outEdges {
            drawOutEdge(edge, midY: midY, height: size.height, in: context)
        }

        drawDot(midY: midY, in: context)
    }

    /// In-edge: enters at the TOP of this row at `fromColumn`, lands on this
    /// row's dot (or through-lane) at `toColumn` on the midline.
    ///   - Straight case (`fromColumn == toColumn`): single vertical line
    ///     from `y=0` down to `y=midY`.
    ///   - Bent case: vertical stub (`y=0` → `y=midY - stubHeight`) at
    ///     `fromX`, then diagonal to `(toX, midY)`.
    private func drawInEdge(_ edge: LaneEdge, midY: CGFloat, in context: GraphicsContext) {
        let fromX = columnX(edge.fromColumn)
        let toX = columnX(edge.toColumn)

        var path = Path()
        if edge.fromColumn == edge.toColumn {
            path.move(to: CGPoint(x: fromX, y: 0))
            path.addLine(to: CGPoint(x: toX, y: midY))
        } else {
            path.move(to: CGPoint(x: fromX, y: 0))
            path.addLine(to: CGPoint(x: fromX, y: midY - Self.stubHeight))
            path.addLine(to: CGPoint(x: toX, y: midY))
        }
        context.stroke(path, with: .color(edge.color.swiftUIColor), lineWidth: Self.lineWidth)
    }

    /// Out-edge: leaves this row's dot (or through-lane) at `fromColumn` on
    /// the midline, exits at the BOTTOM of this row at `toColumn`.
    ///   - Straight case: single vertical line from `(fromX, midY)` to
    ///     `(toX, height)`.
    ///   - Bent case: diagonal from `(fromX, midY)` to
    ///     `(toX, midY + stubHeight)`, then vertical stub to `(toX, height)`.
    private func drawOutEdge(_ edge: LaneEdge, midY: CGFloat, height: CGFloat, in context: GraphicsContext) {
        let fromX = columnX(edge.fromColumn)
        let toX = columnX(edge.toColumn)

        var path = Path()
        if edge.fromColumn == edge.toColumn {
            path.move(to: CGPoint(x: fromX, y: midY))
            path.addLine(to: CGPoint(x: toX, y: height))
        } else {
            path.move(to: CGPoint(x: fromX, y: midY))
            path.addLine(to: CGPoint(x: toX, y: midY + Self.stubHeight))
            path.addLine(to: CGPoint(x: toX, y: height))
        }
        context.stroke(path, with: .color(edge.color.swiftUIColor), lineWidth: Self.lineWidth)
    }

    /// Draws the commit dot at the row's column, then optionally overlays a
    /// selection ring in the system accent color. The fill color prefers the
    /// first out-edge originating at this row's column (which carries the
    /// first-parent lane color per `GraphLayout`) and falls back to the
    /// commit-SHA-seeded palette color for leaf rows with no out-edges.
    private func drawDot(midY: CGFloat, in context: GraphicsContext) {
        let centerX = columnX(row.column)
        let radius = hasRef ? Self.dotRadius + 1 : Self.dotRadius

        let fillColor: LaneColor = row.outEdges.first(where: { $0.fromColumn == row.column })?.color
            ?? LanePalette.color(for: row.commit.sha)

        let rect = CGRect(
            x: centerX - radius,
            y: midY - radius,
            width: radius * 2,
            height: radius * 2
        )
        let dotPath = Path(ellipseIn: rect)
        context.fill(dotPath, with: .color(fillColor.swiftUIColor))

        if isSelected {
            let ringRadius = radius + 2
            let ringRect = CGRect(
                x: centerX - ringRadius,
                y: midY - ringRadius,
                width: ringRadius * 2,
                height: ringRadius * 2
            )
            context.stroke(Path(ellipseIn: ringRect), with: .color(.accentColor), lineWidth: 2)
        }
    }

    /// Center x-coordinate for a given column index. Lanes are 14pt wide and
    /// their contents (dot centers, vertical edge lines) live at
    /// `column * laneWidth + laneWidth / 2`.
    func columnX(_ column: Int) -> CGFloat {
        CGFloat(column) * Self.laneWidth + Self.laneWidth / 2
    }
}
