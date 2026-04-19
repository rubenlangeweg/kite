import SwiftUI

/// One row in the branch list. Used for both local and remote branches;
/// remote rows are rendered slightly muted via `isRemote`.
///
/// Visual contract:
/// - current local branch is rendered with a filled blue dot + semibold name
/// - every row has a leading branch SF Symbol
/// - right-side pills render upstream status (ahead/behind, no upstream, gone)
struct BranchRow: View {
    let branch: Branch

    /// When true, render with secondary text colour. Passed by the view
    /// containing remote branches so they read as "tracked, not owned".
    var isRemote: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Group {
                if branch.isHead {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.tint)
                        .imageScale(.small)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(isRemote ? .secondary : .primary)
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 16)

            Text(branch.shortName)
                .font(.body)
                .fontWeight(branch.isHead ? .semibold : .regular)
                .foregroundStyle(isRemote ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            pills
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .help(helpText)
        .accessibilityIdentifier("BranchRow.\(branch.shortName)")
        .accessibilityLabel(Text(accessibilityLabel))
    }

    // MARK: - Pills

    @ViewBuilder
    private var pills: some View {
        if !isRemote, branch.isGone {
            pill(text: "gone", style: .destructive)
        }
        if !isRemote, !branch.isGone, let ahead = branch.ahead, let behind = branch.behind,
           branch.upstream != nil
        {
            if ahead == 0, behind == 0 {
                pill(text: "in sync", style: .neutral)
            } else {
                if ahead > 0 {
                    pill(text: "\(ahead) ahead", style: .positive)
                }
                if behind > 0 {
                    pill(text: "\(behind) behind", style: .warning)
                }
            }
        } else if !isRemote, branch.upstream == nil, !branch.isGone {
            pill(text: "no upstream", style: .neutral)
        }
    }

    private func pill(text: String, style: PillStyle) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(style.background, in: Capsule())
            .foregroundStyle(style.foreground)
    }

    private var accessibilityLabel: String {
        var parts: [String] = [branch.shortName]
        if branch.isHead { parts.append("current branch") }
        if isRemote { parts.append("remote") }
        if branch.isGone { parts.append("upstream gone") }
        if let ahead = branch.ahead, ahead > 0 { parts.append("\(ahead) ahead") }
        if let behind = branch.behind, behind > 0 { parts.append("\(behind) behind") }
        if branch.upstream == nil, !branch.isGone, !isRemote { parts.append("no upstream") }
        return parts.joined(separator: ", ")
    }

    private var helpText: String {
        if let upstream = branch.upstream {
            return "\(branch.shortName) → \(upstream)"
        }
        return branch.shortName
    }
}

private enum PillStyle {
    case neutral
    case positive
    case warning
    case destructive

    var background: Color {
        switch self {
        case .neutral:
            Color.secondary.opacity(0.15)
        case .positive:
            Color.green.opacity(0.18)
        case .warning:
            Color.orange.opacity(0.22)
        case .destructive:
            Color.red.opacity(0.22)
        }
    }

    var foreground: Color {
        switch self {
        case .neutral:
            .secondary
        case .positive:
            .green
        case .warning:
            .orange
        case .destructive:
            .red
        }
    }
}
