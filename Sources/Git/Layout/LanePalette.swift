import Foundation

/// A fixed 6-color palette slot for a graph lane. Raw values match the
/// documented palette order in `library/git-graph-rendering.md` §3 — the
/// consuming SwiftUI renderer (M4-graph-row-view) maps each case to its
/// actual `Color`.
enum LaneColor: Int, Equatable, CaseIterable, Codable {
    case blue = 0
    case purple
    case orange
    case green
    case pink
    case teal
}

/// Deterministic name → palette-slot mapping for graph lanes.
///
/// We deliberately do NOT use Swift's `Hasher` / `String.hashValue` because
/// those are per-process randomized for security — two runs of the same input
/// would produce different colors, breaking VAL-GRAPH-004 (stable colors
/// across refresh). Instead we hash with FNV-1a-32 over the UTF-8 bytes of
/// the name, which is stable across runs, platforms, and Swift versions.
///
/// A small set of common trunk branch names are hardcoded to `.blue` so the
/// user's main line always renders in the documented primary color,
/// independent of hash collisions (VAL-GRAPH-005).
///
/// Fulfills VAL-GRAPH-004 and VAL-GRAPH-005.
enum LanePalette {
    /// Trunk aliases that always resolve to `.blue`. Listed in descending
    /// order of real-world frequency. `default` is the HEAD label git uses
    /// during detached checkouts and a common CI-ism; include it defensively.
    private static let trunkNames: Set<String> = [
        "main", "master", "trunk", "default", "develop"
    ]

    /// Returns the palette slot for a given lane / branch name.
    static func color(for name: String) -> LaneColor {
        if trunkNames.contains(name) {
            return .blue
        }
        let slotCount = UInt32(LaneColor.allCases.count)
        let slot = fnv1a32(name) % slotCount
        // Safe force-unwrap: `slot` is already clamped to `[0, slotCount)` and
        // `LaneColor` has `slotCount` cases with contiguous raw values 0..<6.
        return LaneColor(rawValue: Int(slot))!
    }

    /// FNV-1a 32-bit hash over the UTF-8 bytes of `input`. Cross-process
    /// stable by construction.
    ///
    /// Constants per http://isthe.com/chongo/tech/comp/fnv/ :
    ///   - offset basis: 0x811c9dc5
    ///   - prime:        0x01000193
    private static func fnv1a32(_ input: String) -> UInt32 {
        var hash: UInt32 = 0x811c_9dc5
        for byte in input.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        return hash
    }
}
