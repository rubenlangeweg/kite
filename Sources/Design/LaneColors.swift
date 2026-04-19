import SwiftUI

/// SwiftUI `Color` mapping for each `LaneColor` palette slot.
///
/// Values are hand-tuned for readable contrast in both Light and Dark Aqua.
/// The stock `.blue` / `.orange` / etc. system colors are avoided for the
/// hues that clash against the Dark-mode control background; those are
/// replaced by slightly-desaturated explicit RGB variants. Blue, orange, and
/// green remain at the system tints because they already look correct
/// against `NSColor.windowBackgroundColor` in both appearances.
///
/// See `library/git-graph-rendering.md` §3 for palette rationale.
extension LaneColor {
    var swiftUIColor: Color {
        switch self {
        case .blue:
            Color.blue
        case .purple:
            // Dark-mode-safe violet — system `.purple` renders too close to
            // pink in Dark Aqua.
            Color(red: 0.58, green: 0.35, blue: 0.80)
        case .orange:
            Color.orange
        case .green:
            Color.green
        case .pink:
            Color.pink
        case .teal:
            Color.teal
        }
    }
}
