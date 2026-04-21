import Foundation
import Observation
import OSLog

/// App-wide service bridging menu / keyboard-shortcut actions to the
/// underlying per-repo services (`NetworkOps`, `BranchOps`, `RepoStore`,
/// `RepoSidebarModel`). Lives alongside the other `@State` models on
/// `KiteApp` and is injected via `.environment(...)` on the WindowGroup +
/// Settings scenes. `KiteCommands` reads it back via `@FocusedValue`.
///
/// Every action is a no-op when no repo is focused (`hasFocus` drives the
/// menu items' `.disabled(...)`), so callers in the menu need only guard
/// with `appCommands?.hasFocus == true` for UX state — the actions
/// themselves are also safe to invoke with no focus.
///
/// ⌘N (open new window) and ⌘, (settings) are intentionally *not* in this
/// service: the former needs the `@Environment(\.openWindow)` value that
/// only lives inside the scene builder, and the latter is auto-wired by
/// SwiftUI's `Settings {}` scene.
///
/// Fulfills: VAL-UI-002 (toolbar + menu parity for refresh/fetch/pull/push/
/// new-branch), VAL-UI-003 (keyboard shortcut map), VAL-UI-009 (new-window
/// action is fired from the menu builder; see `KiteCommands`).
@Observable
@MainActor
final class AppCommands {
    @ObservationIgnored
    private let store: RepoStore

    @ObservationIgnored
    private let networkOps: NetworkOps

    @ObservationIgnored
    private let branchOps: BranchOps

    @ObservationIgnored
    private let sidebar: RepoSidebarModel

    @ObservationIgnored
    private let toasts: ToastCenter

    @ObservationIgnored
    private static let logger = Logger(subsystem: "nl.rb2.kite", category: "ui")

    /// Bumped whenever ⌘⇧N / "New Branch…" fires from the menu. The
    /// toolbar's `NewBranchButton` observes this via `.onChange` and opens
    /// its `NewBranchSheet` — keeps sheet ownership in the view layer while
    /// letting the menu trigger it.
    var newBranchRequest: UUID?

    /// Convenience for CommandMenu's `.disabled(...)` clauses — reads
    /// `store.focus` so menu items re-evaluate when the focus swaps.
    var hasFocus: Bool {
        store.focus != nil
    }

    init(
        store: RepoStore,
        networkOps: NetworkOps,
        branchOps: BranchOps,
        sidebar: RepoSidebarModel,
        toasts: ToastCenter
    ) {
        self.store = store
        self.networkOps = networkOps
        self.branchOps = branchOps
        self.sidebar = sidebar
        self.toasts = toasts
    }

    // MARK: - Actions

    /// ⌘R: refresh the focused repo's UI state.
    ///
    /// Two things happen in parallel:
    ///   1. `RepoSidebarModel.refresh()` — re-scans roots so sidebar adds /
    ///      drops reflect the latest on-disk state.
    ///   2. `RepoFocus.forceRefresh()` — bumps `lastChangeAt` so every
    ///      `onChange(of: focus.lastChangeAt)` observer (branch list,
    ///      status header, graph, diffs) re-pulls from git.
    ///
    /// Does not trigger a network fetch — ⌘⇧F is the explicit surface for
    /// that. ⌘R stays local so it's safe to mash.
    func refreshFocused() async {
        await sidebar.refresh()
        store.focus?.forceRefresh()
    }

    /// ⌘⇧F: `git fetch --all --prune` against the focused repo.
    /// No-op (and no toast) when nothing is focused.
    func fetchFocused() async {
        guard let focus = store.focus else { return }
        _ = await networkOps.fetch(on: focus)
    }

    /// ⌘⇧P: `git pull --ff-only` against the focused repo.
    /// No-op when nothing is focused.
    func pullFocused() async {
        guard let focus = store.focus else { return }
        _ = await networkOps.pullFFOnly(on: focus)
    }

    /// ⌘⇧K: `git push` (no force) against the focused repo.
    ///
    /// Parallels `PushToolbarButton`'s Task body: resolves the current
    /// branch name via `git symbolic-ref --short HEAD`, then dispatches to
    /// `NetworkOps.push(on:currentBranch:)`. On `.needsUpstream` we route to
    /// an error toast telling the user to use the toolbar Push button — the
    /// confirmation sheet (VAL-NET-003) lives on that button's view, and
    /// we'd rather direct the user there than silently push with upstream
    /// set (which would bypass the confirmation UX).
    func pushFocused() async {
        guard let focus = store.focus else { return }
        let currentBranch = await Self.readCurrentBranch(cwd: focus.repo.url)
        let outcome = await networkOps.push(on: focus, currentBranch: currentBranch)
        switch outcome {
        case .success, .failed:
            return
        case .needsUpstream:
            // Keep the confirmation-sheet surface on PushToolbarButton so we
            // don't add a second sheet entry point. Ping the user instead.
            toasts.error(
                "Branch has no upstream. Use the toolbar Push button to set one.",
                detail: nil
            )
        }
    }

    /// ⌘⇧N: bump the sheet request so the toolbar's `NewBranchButton`
    /// opens its sheet. Returns without bumping when no repo is focused so
    /// the button (which also gates on `store.focus != nil`) doesn't flash
    /// a sheet against a nil focus.
    func openNewBranchSheet() {
        guard hasFocus else { return }
        newBranchRequest = UUID()
    }

    // MARK: - Private

    /// Best-effort: read the current branch for the repo at `cwd`. Returns
    /// nil for a detached HEAD. Mirrors `PushToolbarButton.readCurrentBranch`.
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
