import SwiftUI

/// Empty-state content for the repo sidebar (VAL-UI-007).
///
/// Appears when no roots contain discoverable repos and nothing is pinned.
/// The "Add folder…" button routes to the Settings scene via the built-in
/// SwiftUI `openSettings` action — the Settings Roots tab itself is owned by
/// the M2-settings-roots feature.
struct EmptyRepoList: View {
    @Environment(\.openSettings) private var openSettings

    /// Default root shown in the description. Parameterised so snapshot
    /// tests can pin the output to a stable string regardless of the
    /// test machine's home directory.
    var defaultRootDisplay: String = "~/Developer"

    var body: some View {
        ContentUnavailableView {
            Label("No repositories", systemImage: "folder.badge.questionmark")
        } description: {
            Text(
                "Kite didn't find any git repositories in \(defaultRootDisplay). Add another folder in Settings to look elsewhere."
            )
        } actions: {
            Button("Add folder…") {
                openSettings()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("RepoSidebar.EmptyState.AddFolderButton")
        }
        .accessibilityIdentifier("RepoSidebar.EmptyState")
    }
}
