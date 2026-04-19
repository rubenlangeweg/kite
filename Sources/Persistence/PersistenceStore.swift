import CoreGraphics
import Foundation
import Observation

/// `@Observable` façade over the Codable `KiteSettings` value persisted in
/// `UserDefaults`.
///
/// Design:
///
/// - One aggregate JSON blob stored at `PersistenceKeys.settingsBlob`. Atomic
///   reads and writes, trivial migration story.
/// - `init(defaults:)` eagerly loads on construction. Missing-key and
///   corrupt-blob scenarios both fall back to `KiteSettings.default` and persist
///   it immediately — callers can assume `settings` is always valid.
/// - `save()` is synchronous. The payload is tiny (< 4 KB even with dozens of
///   repos) and `UserDefaults` batches its on-disk flushes, so the cost of a
///   `set(_:forKey:)` call is just a dictionary write.
/// - The `defaults` parameter is injectable so tests can use an isolated
///   `UserDefaults(suiteName:)` rather than mutating `.standard`.
///
/// Fulfills: VAL-PERSIST-001…005 (at the unit/API level; UI wiring lands in
/// M2-repo-sidebar and the per-feature views that consume PersistenceStore).
@Observable
@MainActor
final class PersistenceStore {
    private let defaults: UserDefaults

    /// The currently-live settings. Read by every view that binds persistence;
    /// written via the typed mutators below or directly then followed by
    /// `save()`.
    private(set) var settings: KiteSettings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loaded = Self.load(from: defaults)
        settings = loaded.settings
        if loaded.persistDefaults {
            // First-run or recovery-from-corruption: persist the defaults so
            // subsequent launches skip the fallback branch.
            Self.write(loaded.settings, to: defaults)
        }
    }

    /// Persist the current settings snapshot. Safe to call from any main-actor
    /// context; synchronous.
    func save() {
        Self.write(settings, to: defaults)
    }

    // MARK: - Typed mutators

    /// Pin a repo by absolute path. Duplicates are ignored; order preserved
    /// (existing position wins for already-pinned paths).
    func pin(_ path: String) {
        guard !settings.pinnedRepos.contains(path) else { return }
        settings.pinnedRepos.append(path)
        save()
    }

    /// Unpin a repo. No-op when the path isn't pinned.
    func unpin(_ path: String) {
        let before = settings.pinnedRepos.count
        settings.pinnedRepos.removeAll { $0 == path }
        if settings.pinnedRepos.count != before {
            save()
        }
    }

    /// Add an extra scan root. Throws when the path is missing or not a
    /// directory — VAL-REPO-005 wants invalid roots surfaced, not silently
    /// accepted.
    func addExtraRoot(_ path: String) throws {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        guard exists else {
            throw ExtraRootError.pathDoesNotExist(path)
        }
        guard isDirectory.boolValue else {
            throw ExtraRootError.notADirectory(path)
        }
        guard !settings.extraRoots.contains(path) else { return }
        settings.extraRoots.append(path)
        save()
    }

    /// Remove an extra scan root. No-op when absent.
    func removeExtraRoot(_ path: String) {
        let before = settings.extraRoots.count
        settings.extraRoots.removeAll { $0 == path }
        if settings.extraRoots.count != before {
            save()
        }
    }

    func setLastOpenedRepo(_ path: String?) {
        settings.lastOpenedRepo = path
        save()
    }

    func setLastSelectedBranch(_ branch: String, forRepo repo: String) {
        settings.lastSelectedBranch[repo] = branch
        save()
    }

    func setWindowFrame(_ rect: CGRect) {
        settings.windowFrame = CGRectValue(rect)
        save()
    }

    func setSidebarWidth(_ width: Double) {
        settings.sidebarWidth = width
        save()
    }

    func setDetailWidth(_ width: Double) {
        settings.detailWidth = width
        save()
    }

    func setAutoFetchEnabled(_ enabled: Bool) {
        settings.autoFetchEnabled = enabled
        save()
    }

    // MARK: - Errors

    enum ExtraRootError: Error, LocalizedError, Equatable {
        case pathDoesNotExist(String)
        case notADirectory(String)

        var errorDescription: String? {
            switch self {
            case let .pathDoesNotExist(path):
                "Path does not exist: \(path)"
            case let .notADirectory(path):
                "Not a directory: \(path)"
            }
        }
    }

    // MARK: - Internal load/save

    /// Result of a load attempt plus a flag telling the caller whether the
    /// defaults should be written back to `UserDefaults` right away. We flush
    /// defaults on first-launch and after corruption so the next launch hits
    /// the fast path.
    private struct LoadOutcome {
        let settings: KiteSettings
        let persistDefaults: Bool
    }

    private static func load(from defaults: UserDefaults) -> LoadOutcome {
        guard let data = defaults.data(forKey: PersistenceKeys.settingsBlob) else {
            return LoadOutcome(settings: .default, persistDefaults: true)
        }
        do {
            let decoded = try migrate(data)
            return LoadOutcome(settings: decoded, persistDefaults: false)
        } catch {
            // Resilience contract: corrupt UserDefaults must never crash the
            // app. Fall back to defaults and persist over the garbage so the
            // user isn't stuck reading broken data every launch.
            return LoadOutcome(settings: .default, persistDefaults: true)
        }
    }

    private static func write(_ settings: KiteSettings, to defaults: UserDefaults) {
        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: PersistenceKeys.settingsBlob)
        } catch {
            // JSONEncoder only throws for non-Codable inputs; `KiteSettings` is
            // fully Codable so this path is unreachable in practice. If it
            // ever does hit (e.g. a future field forgets Codable conformance),
            // swallowing here keeps the app alive and the fault visible via
            // the caller's next load-then-compare.
        }
    }

    /// Decode `data` and run any needed migrations to reach `KiteSettings.current`.
    /// v1 is the baseline schema so the migration is a plain decode.
    private static func migrate(_ data: Data) throws -> KiteSettings {
        let decoder = JSONDecoder()
        // Peek at the version first so future migrations can dispatch on it
        // without forcing a full decode to succeed against a new layout.
        let probe = try decoder.decode(SchemaProbe.self, from: data)
        switch probe.schemaVersion {
        case KiteSettings.current:
            return try decoder.decode(KiteSettings.self, from: data)
        default:
            // No historical versions yet. A future M-n feature would add a
            // case per supported prior version, transform the decoded old
            // struct into `KiteSettings.current`, and return it.
            throw MigrationError.unsupportedSchemaVersion(probe.schemaVersion)
        }
    }

    private struct SchemaProbe: Decodable {
        let schemaVersion: Int
    }

    enum MigrationError: Error, Equatable {
        case unsupportedSchemaVersion(Int)
    }
}
