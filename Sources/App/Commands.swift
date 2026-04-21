import SwiftUI

/// Top-level command builder for Kite's menu bar + keyboard shortcuts.
///
/// Actions route through `AppCommands`, which is injected via
/// `.focusedSceneValue(\.appCommands, ...)` on the WindowGroup. SwiftUI
/// passes each window's focused scene value into the `Commands` builder
/// via `@FocusedValue`, so switching windows picks up the right service
/// instance automatically.
///
/// Shortcut coverage (VAL-UI-003):
///   - ⌘R          Refresh focused repo
///   - ⌘⇧F         Fetch
///   - ⌘⇧P         Pull (fast-forward only)
///   - ⌘⇧K         Push
///   - ⌘⇧N         New branch
///   - ⌘N          New window (CommandGroup replacing `.newItem`)
///   - ⌘,          Settings (SwiftUI auto-wires via the `Settings {}` scene)
///
/// ⌘T (switch branch) is intentionally deferred: there is no branch-picker
/// UI in v1 for the shortcut to invoke — switching is driven by
/// double-clicking a branch row in the list. Deferred to a follow-up
/// feature once a dedicated branch picker exists.
///
/// Fulfills: VAL-UI-002 (menu parity with toolbar), VAL-UI-003 (shortcut
/// map), VAL-UI-009 (⌘N opens a second independent window).
struct KiteCommands: Commands {
    @FocusedValue(\.appCommands) private var appCommands: AppCommands?
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Replace the default File > New Window with our explicit opener —
        // SwiftUI's built-in `.newItem` group still exposes ⌘N, but having
        // our own button makes the label explicit ("New Window") and keeps
        // the binding locked even as SwiftUI evolves the default.
        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                openWindow(id: "main")
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu("Repository") {
            Button("Refresh") {
                let commands = appCommands
                Task { await commands?.refreshFocused() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(appCommands?.hasFocus != true)

            Divider()

            Button("Fetch") {
                let commands = appCommands
                Task { await commands?.fetchFocused() }
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(appCommands?.hasFocus != true)

            Button("Pull (fast-forward only)") {
                let commands = appCommands
                Task { await commands?.pullFocused() }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(appCommands?.hasFocus != true)

            Button("Push") {
                let commands = appCommands
                Task { await commands?.pushFocused() }
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(appCommands?.hasFocus != true)

            Divider()

            Button("New Branch…") {
                appCommands?.openNewBranchSheet()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(appCommands?.hasFocus != true)
        }
    }
}

/// `FocusedValueKey` carrying the focused window's `AppCommands` instance.
/// `KiteCommands` reads this via `@FocusedValue(\.appCommands)`. A second
/// window spawned via ⌘N gets its own `.focusedSceneValue` injection, so
/// each menu invocation targets the frontmost window's service.
struct AppCommandsFocusedKey: FocusedValueKey {
    typealias Value = AppCommands
}

extension FocusedValues {
    var appCommands: AppCommands? {
        get { self[AppCommandsFocusedKey.self] }
        set { self[AppCommandsFocusedKey.self] = newValue }
    }
}
