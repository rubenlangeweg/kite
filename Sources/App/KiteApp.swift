import OSLog
import SwiftUI

@main
struct KiteApp: App {
    @State private var persistence: PersistenceStore
    @State private var repoStore: RepoStore
    @State private var sidebarModel: RepoSidebarModel

    init() {
        let store = PersistenceStore()
        // XCUITest hooks: only honoured when running under XCTest. In production
        // the env var is absent, so these args can never reach real prefs even
        // if someone passes them by accident. See `isRunningUnderXCTest`.
        if Self.isRunningUnderXCTest {
            KiteApp.applyFixtureExtraRoots(to: store)
        }

        _persistence = State(wrappedValue: store)

        let repos = RepoStore(persistence: store)
        _repoStore = State(wrappedValue: repos)

        let rootsOverride = Self.isRunningUnderXCTest ? KiteApp.fixtureRootsFromLaunchArgs() : nil
        let model = RepoSidebarModel(persistence: store, repoStore: repos, rootsOverride: rootsOverride)
        _sidebarModel = State(wrappedValue: model)
    }

    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var body: some Scene {
        WindowGroup("Kite") {
            RootView()
                .frame(minWidth: 900, minHeight: 600)
                .environment(persistence)
                .environment(repoStore)
                .environment(sidebarModel)
        }
        .windowResizability(.contentSize)
        .commands {
            KiteCommands()
        }

        Settings {
            SettingsRootView()
                .environment(persistence)
                .environment(repoStore)
                .environment(sidebarModel)
        }
    }

    /// Parse `-KITE_FIXTURE_ROOTS <comma-separated-paths>` out of the process
    /// argument vector. Returns nil when the flag is absent. Honoured only for
    /// XCUITest — real launches never inject this.
    private static func fixtureRootsFromLaunchArgs() -> [URL]? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-KITE_FIXTURE_ROOTS"), idx + 1 < args.count else {
            return nil
        }
        let raw = args[idx + 1]
        let paths = raw.split(separator: ",", omittingEmptySubsequences: true).map(String.init)
        guard !paths.isEmpty else { return [] }
        return paths.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    }

    /// Parse `-KITE_FIXTURE_EXTRA_ROOTS <colon-separated-paths>` and seed the
    /// store's extra-roots list. Tests use this to stage a specific extra-roots
    /// state before launching the app — real launches ignore it.
    ///
    /// Colons match the UNIX `PATH` separator convention so test fixtures
    /// don't collide with commas that can appear in legitimate path names.
    private static func applyFixtureExtraRoots(to store: PersistenceStore) {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-KITE_FIXTURE_EXTRA_ROOTS"), idx + 1 < args.count else {
            return
        }
        let raw = args[idx + 1]
        let paths = raw.split(separator: ":", omittingEmptySubsequences: true).map(String.init)
        for path in paths {
            let expanded = (path as NSString).expandingTildeInPath
            // Best-effort add. Invalid paths are logged but not raised —
            // XCUITests that want invalid-path UI coverage invoke the
            // Settings UI's Add flow instead of relying on pre-seeded bad
            // state.
            do {
                try store.addExtraRoot(expanded)
            } catch {
                Logger(subsystem: "nl.rb2.kite", category: "app")
                    .error("applyFixtureExtraRoots dropped \(expanded, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
