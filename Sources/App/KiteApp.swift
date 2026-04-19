import SwiftUI

@main
struct KiteApp: App {
    var body: some Scene {
        WindowGroup("Kite") {
            RootView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowResizability(.contentSize)
        .commands {
            KiteCommands()
        }

        Settings {
            SettingsPlaceholderView()
        }
    }
}

private struct SettingsPlaceholderView: View {
    var body: some View {
        Text("Settings")
            .frame(width: 480, height: 320)
    }
}
