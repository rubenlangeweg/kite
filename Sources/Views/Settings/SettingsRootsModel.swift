import Foundation
import Observation
import OSLog

/// Helper type for `SettingsRootsTab` that holds all of the logic that doesn't
/// belong in SwiftUI view builder code: status probing, default-root derivation,
/// add/remove wrappers around `PersistenceStore`, and error formatting.
///
/// Extracted so VAL-REPO-003/004/005 can be unit-tested without instantiating
/// a SwiftUI view graph.
///
/// Fulfills: VAL-REPO-003 / VAL-REPO-004 / VAL-REPO-005 (logic layer).
@Observable
@MainActor
final class SettingsRootsModel {
    @ObservationIgnored
    private let persistence: PersistenceStore

    @ObservationIgnored
    private let fileManager: FileManager

    @ObservationIgnored
    private static let logger = Logger(subsystem: "nl.rb2.kite", category: "ui")

    /// Inline error message shown below the "Add folder…" button. Cleared by
    /// the view after a short delay; directly cleared by a successful add.
    var inlineError: String?

    init(persistence: PersistenceStore, fileManager: FileManager = .default) {
        self.persistence = persistence
        self.fileManager = fileManager
    }

    // MARK: - Default root

    /// The immutable default scan root: `~/Developer`. Matches
    /// `RepoSidebarModel.defaultRoot`.
    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Developer")
    }

    /// Default root, abbreviated to `~/Developer` for display.
    static var defaultRootDisplay: String {
        "~/Developer"
    }

    // MARK: - Row model

    /// Status of a scan root on disk.
    enum RootStatus: Equatable {
        case found
        case missing
    }

    /// One row in the roots table. Either the default `~/Developer` or an
    /// extra root added via Settings. Default rows cannot be removed.
    struct RootRow: Identifiable, Equatable {
        let path: String
        let displayPath: String
        let isDefault: Bool
        let status: RootStatus

        var id: String {
            path
        }
    }

    /// Compute the ordered row list: default root first, then extras in
    /// persistence order. Pulls status for each row from the filesystem.
    var rows: [RootRow] {
        var result: [RootRow] = []
        let defaultPath = Self.defaultRoot.path
        result.append(
            RootRow(
                path: defaultPath,
                displayPath: Self.defaultRootDisplay,
                isDefault: true,
                status: status(forPath: defaultPath)
            )
        )
        for extra in persistence.settings.extraRoots {
            let expanded = (extra as NSString).expandingTildeInPath
            result.append(
                RootRow(
                    path: expanded,
                    displayPath: Self.abbreviate(path: expanded),
                    isDefault: false,
                    status: status(forPath: expanded)
                )
            )
        }
        return result
    }

    /// Determine on-disk status for a path (exists + is a directory → found).
    func status(forPath path: String) -> RootStatus {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
        return (exists && isDirectory.boolValue) ? .found : .missing
    }

    // MARK: - Mutations

    /// Add an extra root. Surfaces any thrown error as a user-friendly message
    /// on `inlineError` and returns false. Caller is responsible for running
    /// the sidebar refresh on success.
    @discardableResult
    func addRoot(path: String) -> Bool {
        do {
            try persistence.addExtraRoot(path)
            inlineError = nil
            return true
        } catch let error as PersistenceStore.ExtraRootError {
            inlineError = Self.userFacingMessage(for: error)
            Self.logger.error("addExtraRoot failed: \(error.localizedDescription, privacy: .public)")
            return false
        } catch {
            inlineError = "Couldn't add folder: \(error.localizedDescription)"
            Self.logger.error("addExtraRoot failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Remove an extra root. Default root is protected — attempting to remove
    /// it is a no-op that returns false.
    @discardableResult
    func removeRoot(path: String) -> Bool {
        if path == Self.defaultRoot.path {
            return false
        }
        persistence.removeExtraRoot(path)
        return true
    }

    /// Convenience for views: the set of currently persisted extra roots.
    /// Exposed so tests can assert persistence state without poking at the
    /// store directly.
    var extraRoots: [String] {
        persistence.settings.extraRoots
    }

    // MARK: - Private helpers

    private static func userFacingMessage(for error: PersistenceStore.ExtraRootError) -> String {
        switch error {
        case let .pathDoesNotExist(path):
            "That folder doesn't exist: \(abbreviate(path: path))"
        case let .notADirectory(path):
            "That path isn't a folder: \(abbreviate(path: path))"
        }
    }

    /// Collapse the user's home directory to `~` for display.
    static func abbreviate(path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home {
            return "~"
        }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
