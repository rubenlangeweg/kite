import SwiftUI

/// Toolbar button that triggers `NetworkOps.push(on:currentBranch:)` against
/// the currently focused repo.
///
/// Runs `git push --progress` without any force flags. On `.needsUpstream`
/// the button presents `UpstreamSetSheet` offering to run
/// `git push --set-upstream <remote> <branch>`. On `.success` or `.failed`
/// the toast surface already reflects the outcome — the sheet is not shown.
///
/// Fulfills: VAL-NET-003 (push without any force flag, upstream-set confirmation),
/// VAL-NET-004 (auth errors route to sticky toast via NetworkOps),
/// VAL-UI-002 (toolbar surface for push).
struct PushToolbarButton: View {
    @Environment(RepoStore.self) private var store
    @Environment(NetworkOps.self) private var ops

    @State private var isRunning: Bool = false
    @State private var upstreamPrompt: UpstreamPrompt?

    /// Transient sheet-input describing the branch / remote that need a
    /// `git push -u` invocation. `Identifiable` so `.sheet(item:)` can key
    /// on each presentation independently.
    struct UpstreamPrompt: Identifiable, Equatable {
        let id: UUID
        let branch: String
        let remote: String

        init(branch: String, remote: String) {
            id = UUID()
            self.branch = branch
            self.remote = remote
        }
    }

    var body: some View {
        Button {
            guard let focus = store.focus else { return }
            isRunning = true
            Task {
                let currentBranch = await Self.readCurrentBranch(cwd: focus.repo.url)
                let outcome = await ops.push(on: focus, currentBranch: currentBranch)
                switch outcome {
                case .success, .failed:
                    break
                case let .needsUpstream(branch, remote):
                    upstreamPrompt = UpstreamPrompt(branch: branch, remote: remote)
                }
                isRunning = false
            }
        } label: {
            Image(systemName: "arrow.up.circle")
        }
        .help("Push")
        .disabled(store.focus == nil || isRunning)
        .accessibilityLabel("Push")
        .accessibilityIdentifier("Toolbar.Push")
        .sheet(item: $upstreamPrompt) { prompt in
            UpstreamSetSheet(branch: prompt.branch, remote: prompt.remote) { confirmed in
                upstreamPrompt = nil
                guard confirmed, let focus = store.focus else { return }
                Task {
                    _ = await ops.pushWithUpstream(on: focus, branch: prompt.branch, remote: prompt.remote)
                }
            }
        }
    }

    /// Best-effort: read the current branch for the focused repo. Returns
    /// nil for a detached HEAD (symbolic-ref exits non-zero). Runs through
    /// `Git.run` which inherits the hardened env block.
    private static func readCurrentBranch(cwd: URL) async -> String? {
        do {
            let result = try await Git.run(args: ["symbolic-ref", "--short", "HEAD"], cwd: cwd)
            guard result.isSuccess else { return nil }
            let branch = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return branch.isEmpty ? nil : branch
        } catch {
            return nil
        }
    }
}

/// Confirmation sheet offering to run `git push --set-upstream <remote> <branch>`.
/// Never auto-confirms — the sheet blocks until the user explicitly chooses
/// Cancel or "Push with upstream".
///
/// Fulfills: VAL-NET-003 (set-upstream confirmation).
struct UpstreamSetSheet: View {
    let branch: String
    let remote: String
    let onComplete: (Bool) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Set upstream for \u{201C}\(branch)\u{201D}?")
                .font(.headline)
                .accessibilityIdentifier("UpstreamSheet.Title")

            Text("Run: `git push -u \(remote) \(branch)`")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack {
                Button("Cancel") {
                    onComplete(false)
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("UpstreamSheet.Cancel")

                Spacer()

                Button("Push with upstream") {
                    onComplete(true)
                }
                .keyboardShortcut(.defaultAction)
                .tint(.accentColor)
                .accessibilityIdentifier("UpstreamSheet.Confirm")
            }
        }
        .padding()
        .frame(width: 380)
        .accessibilityIdentifier("UpstreamSheet")
    }
}
