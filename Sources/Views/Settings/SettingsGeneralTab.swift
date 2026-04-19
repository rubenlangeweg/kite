import SwiftUI

/// General Settings tab. Minimal in this feature — lands the auto-fetch
/// toggle early so `PersistenceStore.autoFetchEnabled` has a UI control
/// before M5-auto-fetch wires the timer itself.
struct SettingsGeneralTab: View {
    @Environment(PersistenceStore.self) private var persistence

    var body: some View {
        Form {
            Section("Auto-fetch") {
                Toggle("Enable auto-fetch on focused repo", isOn: autoFetchBinding)
                    .accessibilityIdentifier("Settings.General.AutoFetchToggle")

                Text("Runs `git fetch --all --prune` every 5 minutes on the repo you're currently viewing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .accessibilityIdentifier("Settings.General")
    }

    private var autoFetchBinding: Binding<Bool> {
        Binding(
            get: { persistence.settings.autoFetchEnabled },
            set: { persistence.setAutoFetchEnabled($0) }
        )
    }
}
