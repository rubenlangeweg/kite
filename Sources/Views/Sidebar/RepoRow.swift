import SwiftUI

/// One repo row in the sidebar list. Shows the repo's display name plus a
/// second line with the parent directory (abbreviated with `~` when it
/// lives under the user's home) and a leading SF Symbol that disambiguates
/// work-tree repos from bare repos (VAL-REPO-006).
struct RepoRow: View {
    let repo: DiscoveredRepo

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Group {
                if repo.isBare {
                    Image(systemName: "cylinder")
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.tint)
                }
            }
            .frame(width: 18)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(repo.displayName)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(parentPathDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            if repo.isBare {
                Text("bare")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("bare repository")
            }
        }
        .padding(.vertical, 2)
        .help(repo.url.path)
        .accessibilityLabel(Text(repo.displayName))
        .accessibilityIdentifier("RepoSidebar.Row.\(repo.displayName)")
    }

    /// Parent directory, with the home prefix collapsed to `~` so long paths
    /// remain readable in the narrow sidebar column.
    private var parentPathDisplay: String {
        let parent = repo.url.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if parent == home {
            return "~"
        }
        if parent.hasPrefix(home + "/") {
            return "~" + parent.dropFirst(home.count)
        }
        return parent
    }
}
