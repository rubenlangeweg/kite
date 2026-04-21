import Foundation

/// Forward-guard constants for release packaging. Surfaces the mission's
/// <20 MB bundle size target (VAL-PKG-005) as a compile-time constant so
/// future features adding resources can see the target before running a
/// full Release build.
enum ReleaseMetadata {
    /// Target maximum bundle size for Kite.app Release build — 20 MB.
    static let targetSizeBytes: Int = 20 * 1024 * 1024

    /// Short version string from the app bundle. Reads from the live
    /// bundle at runtime, falling back to "?" when called outside an
    /// embedded context (e.g. Swift Testing host).
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// Bundle version string from Info.plist. Same fallback rules.
    static var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }
}
