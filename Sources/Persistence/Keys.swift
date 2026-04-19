import Foundation

/// Central registry of every UserDefaults key Kite persists under.
///
/// Two things live here:
///
/// 1. `settingsBlob` — the single aggregate key the `PersistenceStore` reads
///    and writes. The whole `Settings` struct is encoded as one JSON value at
///    this key. Using a single blob (rather than scattering fields across many
///    keys) keeps reads atomic and makes schema-version-driven migrations
///    straightforward: decode, inspect `schemaVersion`, migrate, re-encode.
///
/// 2. `pinnedRepos`, `extraRoots`, `lastOpenedRepo`, `lastSelectedBranch`,
///    `windowFrame`, `sidebarWidth`, `detailWidth`, `autoFetchEnabled` —
///    per-field keys that are **declared but not currently used** by
///    `PersistenceStore`. They stay here as a registry for future features
///    that may want to bind a single scalar directly via `@AppStorage`. Having
///    one source of truth prevents inline string literals cropping up across
///    the codebase (enforced by `AGENTS.md` / INTERFACES.md §4).
///
/// Never use a raw key string outside this file.
enum PersistenceKeys {
    /// Aggregate JSON blob containing the entire `Settings` value.
    static let settingsBlob = "nl.rb2.kite.settings"

    /// Currently unused; declared for future per-field @AppStorage bindings.
    static let schemaVersion = "nl.rb2.kite.schemaVersion"
    static let pinnedRepos = "nl.rb2.kite.pinnedRepos"
    static let extraRoots = "nl.rb2.kite.extraRoots"
    static let lastOpenedRepo = "nl.rb2.kite.lastOpenedRepo"
    static let lastSelectedBranch = "nl.rb2.kite.lastSelectedBranch"
    static let windowFrame = "nl.rb2.kite.windowFrame"
    static let sidebarWidth = "nl.rb2.kite.sidebarWidth"
    static let detailWidth = "nl.rb2.kite.detailWidth"
    static let autoFetchEnabled = "nl.rb2.kite.autoFetchEnabled"
}
