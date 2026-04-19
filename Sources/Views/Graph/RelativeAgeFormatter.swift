import Foundation

/// Compact "time since" formatter used in the commit-graph row.
///
/// Intentionally terse — a row renders at 22pt height and the age column is
/// 64pt wide; long phrases like "6 months ago" overflow. Breakpoints mirror
/// what GitKraken and Fork show:
///
///   < 60s   → "just now"
///   < 1h    → "Nm"
///   < 24h   → "Nh"
///   < 7d    → "Nd"
///   < 30d   → "Nw"
///   < 365d  → "Nmo"
///   else    → "Ny"
///
/// The driving `TimelineView(.periodic(from: .now, by: 60))` in
/// `GraphRowContent` re-renders minute-by-minute so VAL-GRAPH-008 (60fps)
/// isn't blown by per-row timers.
enum RelativeAgeFormatter {
    static func format(from past: Date, now: Date = Date()) -> String {
        let delta = max(0, now.timeIntervalSince(past))

        if delta < 60 {
            return "just now"
        }
        if delta < 3600 {
            return "\(Int(delta / 60))m"
        }
        if delta < 86400 {
            return "\(Int(delta / 3600))h"
        }
        if delta < 86400 * 7 {
            return "\(Int(delta / 86400))d"
        }
        if delta < 86400 * 30 {
            return "\(Int(delta / (86400 * 7)))w"
        }
        if delta < 86400 * 365 {
            return "\(Int(delta / (86400 * 30)))mo"
        }
        return "\(Int(delta / (86400 * 365)))y"
    }
}
