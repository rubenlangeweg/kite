import SwiftUI

/// Small capsule-shaped label rendering a single ref attached to a commit.
///
/// Visual language per library §6 (ref labels):
///   - `.head` — accented blue outlined capsule with bold "HEAD" text; sits
///     next to its branch pill to form the GitKraken-style "HEAD → main"
///     marker. Rendered as an outline so it never flat-dupes a matching local
///     branch pill behind it.
///   - `.localBranch(name)` — solid accent-color fill, white label. Primary
///     visual weight; this is the pill the eye catches first.
///   - `.remoteBranch(remote, branch)` — secondary gray fill with foreground
///     color; a subtler counterpart to the local branch.
///   - `.tag(...)` — returns `EmptyView`. Tag pills are explicitly out of
///     scope for v1 (mission §3 "Out of scope"); the filter at
///     `GraphRowRefs.enrich` already drops them, so this branch is a
///     belt-and-braces guard.
///
/// Typography: `.system(size: 11, weight: .medium, design: .rounded)`. The
/// rounded variant reads better inside a capsule than the default digital
/// shape at 11pt.
struct RefPill: View {
    let kind: RefKind

    var body: some View {
        switch kind {
        case .head:
            pill(text: "HEAD", style: .head)
        case let .localBranch(name):
            pill(text: name, style: .local)
        case let .remoteBranch(remote, branch):
            pill(text: "\(remote)/\(branch)", style: .remote)
        case .tag:
            EmptyView()
        }
    }

    // MARK: - Private

    private enum Style {
        case head
        case local
        case remote
    }

    private func pill(text: String, style: Style) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(foreground(for: style))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background(for: style))
            .overlay(overlay(for: style))
    }

    @ViewBuilder
    private func background(for style: Style) -> some View {
        switch style {
        case .head:
            // Outlined pill: keep the background clear so the ring reads as an
            // outline, not a filled capsule with a darker border.
            Capsule().fill(Color.clear)
        case .local:
            Capsule().fill(Color.accentColor)
        case .remote:
            Capsule().fill(Color.secondary.opacity(0.22))
        }
    }

    @ViewBuilder
    private func overlay(for style: Style) -> some View {
        switch style {
        case .head:
            Capsule().strokeBorder(Color.accentColor, lineWidth: 1)
        case .local:
            Capsule().strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 0.5)
        case .remote:
            Capsule().strokeBorder(Color.secondary.opacity(0.35), lineWidth: 0.5)
        }
    }

    private func foreground(for style: Style) -> Color {
        switch style {
        case .head:
            Color.accentColor
        case .local:
            Color.white
        case .remote:
            Color.primary.opacity(0.85)
        }
    }
}
