import SwiftUI

/// Placeholder command builder. Real keyboard shortcuts wire in during M8-commands-and-menu.
/// Settings (⌘,) is provided automatically by the Settings scene in KiteApp.
struct KiteCommands: Commands {
    var body: some Commands {
        EmptyCommands()
    }
}

private struct EmptyCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
    }
}
