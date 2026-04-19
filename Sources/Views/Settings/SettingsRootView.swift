import SwiftUI

/// Top-level Settings scene body: a `TabView` with General / Roots / About
/// tabs. Named `SettingsRootView` — not `SettingsView` — to avoid a collision
/// with SwiftUI's `Settings` scene type per AGENTS.md.
///
/// Fulfills VAL-UI-008 (Settings reachable via ⌘,) — SwiftUI's native
/// `Settings { ... }` scene binds the ⌘, shortcut automatically.
struct SettingsRootView: View {
    var body: some View {
        TabView {
            SettingsGeneralTab()
                .tabItem { Label("General", systemImage: "gear") }
                .accessibilityIdentifier("Settings.Tab.General")

            SettingsRootsTab()
                .tabItem { Label("Roots", systemImage: "folder") }
                .accessibilityIdentifier("Settings.Tab.Roots")

            SettingsAboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
                .accessibilityIdentifier("Settings.Tab.About")
        }
        .frame(width: 520, height: 380)
        .accessibilityIdentifier("Settings.Root")
    }
}
