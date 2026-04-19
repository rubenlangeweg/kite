import SwiftUI

@main
struct KiteApp: App {
    @State private var persistence: PersistenceStore
    @State private var sidebarModel: RepoSidebarModel

    init() {
        let store = PersistenceStore()
        // XCUITest hook: `-KITE_FIXTURE_EXTRA_ROOTS <path>[:<path>...]` seeds
        // the persisted extra-roots list before any view binds. Only honoured
        // for UI tests; production launches never inject this argument.
        KiteApp.applyFixtureExtraRoots(to: store)

        _persistence = State(wrappedValue: store)

        // XCUITest hook: `-KITE_FIXTURE_ROOTS <path>[,<path>...]` overrides
        // the default `~/Developer` root with test-provided fixture directories.
        // Only honoured for UI tests; normal launches ignore it.
        let rootsOverride = KiteApp.fixtureRootsFromLaunchArgs()
        let model = RepoSidebarModel(persistence: store, rootsOverride: rootsOverride)
        _sidebarModel = State(wrappedValue: model)
    }

    var body: some Scene {
        WindowGroup("Kite") {
            RootView()
                .frame(minWidth: 900, minHeight: 600)
                .environment(persistence)
                .environment(sidebarModel)
        }
        .windowResizability(.contentSize)
        .commands {
            KiteCommands()
        }

        Settings {
            SettingsRootView()
                .environment(persistence)
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
            // Best-effort add. Paths that don't exist are intentionally
            // dropped here — XCUITests that want invalid-path UI coverage
            // invoke the Settings UI's Add flow instead of relying on
            // pre-seeded bad state.
            try? store.addExtraRoot(expanded)
        }
    }
}
