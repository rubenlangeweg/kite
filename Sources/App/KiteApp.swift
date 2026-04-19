import SwiftUI

@main
struct KiteApp: App {
    @State private var persistence: PersistenceStore
    @State private var sidebarModel: RepoSidebarModel

    init() {
        let store = PersistenceStore()
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
            SettingsPlaceholderView()
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
}

private struct SettingsPlaceholderView: View {
    var body: some View {
        Text("Settings (populated in M2-settings-roots)")
            .frame(width: 480, height: 320)
    }
}
