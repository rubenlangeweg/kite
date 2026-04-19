import CoreGraphics
import Foundation

/// Aggregate, atomically-persisted user settings.
///
/// The whole struct is JSON-encoded and stored at
/// `PersistenceKeys.settingsBlob`. `schemaVersion` is bumped any time the
/// layout changes; `PersistenceStore.migrate(_:)` is the single point at
/// which old blobs are upgraded to `KiteSettings.current`.
///
/// Fulfills VAL-PERSIST-005 (schema versioned).
struct KiteSettings: Codable, Equatable {
    /// Bump whenever any field is added / removed / renamed / reshaped.
    /// Migration logic in `PersistenceStore` reads the encoded version first
    /// and applies transforms before attempting to decode the remainder.
    static let current: Int = 1

    /// Known-good starting state for a brand-new user.
    static var `default`: KiteSettings {
        KiteSettings(
            schemaVersion: current,
            pinnedRepos: [],
            extraRoots: [],
            lastOpenedRepo: nil,
            lastSelectedBranch: [:],
            windowFrame: nil,
            sidebarWidth: nil,
            detailWidth: nil,
            autoFetchEnabled: true
        )
    }

    var schemaVersion: Int
    /// Absolute paths of pinned repos, in display order.
    var pinnedRepos: [String]
    /// Absolute paths of extra scan roots configured in Settings.
    var extraRoots: [String]
    /// Absolute path of the last focused repo. Restored on launch.
    var lastOpenedRepo: String?
    /// Maps repo absolute path → last-selected branch short name.
    var lastSelectedBranch: [String: String]
    /// Main window frame in screen coordinates. nil on first launch.
    var windowFrame: CGRectValue?
    /// NavigationSplitView sidebar column width (points).
    var sidebarWidth: Double?
    /// NavigationSplitView detail column width (points).
    var detailWidth: Double?
    /// Background auto-fetch master switch. Defaults to true.
    var autoFetchEnabled: Bool
}

/// Codable wrapper around `CGRect`.
///
/// `CGRect` picks up `Codable` conformance indirectly on macOS, but its
/// synthesized encoding uses CoreFoundation structural keys that are
/// inconvenient to read and have shifted shape historically. A
/// hand-written wrapper keeps the JSON shape stable and explicit so any
/// future cross-platform or out-of-process consumer (e.g. a command-line
/// debug dumper) can parse it trivially.
struct CGRectValue: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: CGRect) {
        x = Double(rect.origin.x)
        y = Double(rect.origin.y)
        width = Double(rect.size.width)
        height = Double(rect.size.height)
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}
