import SwiftUI

/// Toolbar-resident progress indicator. Shows:
///   - a circular indeterminate spinner while the first active op has nil
///     percent (e.g. the stdin-less phase of a fetch before `ProgressParser`
///     locks onto "Receiving objects: NN%").
///   - a linear determinate bar once `percent` is populated.
///
/// When `progress.active` is empty the view collapses to a 0-width spacer so
/// the toolbar layout doesn't shift between idle and active states.
///
/// Fulfills: VAL-UI-006.
struct ToolbarProgressIndicator: View {
    @Environment(ProgressCenter.self) private var progress

    var body: some View {
        Group {
            if let item = progress.active.first {
                HStack(spacing: 6) {
                    if let pct = item.percent {
                        ProgressView(value: Double(max(0, min(pct, 100))) / 100)
                            .progressViewStyle(.linear)
                            .frame(width: 90)
                            .accessibilityIdentifier("ToolbarProgress.Linear")
                    } else {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                            .accessibilityIdentifier("ToolbarProgress.Spinner")
                    }
                    Text(item.label)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
            } else {
                // Collapse to zero width so the toolbar's other items don't
                // shuffle when an op begins/ends. A bare EmptyView would do
                // the same, but an explicit zero-sized Color makes the
                // intent obvious in the view hierarchy debugger.
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .accessibilityIdentifier("ToolbarProgress")
    }
}
