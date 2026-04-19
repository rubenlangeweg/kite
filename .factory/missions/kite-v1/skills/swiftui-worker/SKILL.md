---
name: swiftui-worker
description: Implements SwiftUI views, ViewModels, App scenes, toolbars, menus, keyboard commands, settings, toasts, and persistence for the Kite macOS app. Owns everything under Sources/App, Sources/Views, Sources/ViewModels, Sources/Persistence, Sources/Design, Resources/, Info.plist, Xcode project settings, and Tests/ViewTests + Tests/KiteUITests. Does NOT touch git engine, parsers, layout algorithm, or repo scanner. Reads from the git engine via typed models.
---

# swiftui-worker

## When to use

Route to this worker when a feature involves:

- SwiftUI views, layouts, animations
- Xcode project configuration, scheme, entitlements, Info.plist
- App icon, Assets.xcassets, resources
- App entry point, Scenes, Commands, Settings window
- Toast banners, toolbar, menu bar
- ViewModels binding views to the git engine (but not the git engine itself)
- UserDefaults + Codable persistence
- XCUITest + snapshot tests for views

Features likely to use this worker: M1-project-scaffold, M1-persistence, M2-repo-sidebar, M2-settings-roots, M3-branch-list, M3-status-header, M4-graph-row-view, M4-graph-row-meta, M4-graph-scroll-container, M5-toast-infrastructure, M5-fetch, M5-pull-push, M5-auto-fetch, M6-create-branch, M6-switch-branch, M7-uncommitted-diff, M7-commit-diff, M8-commands-and-menu, M8-app-icon-and-plist, M8-release-packaging.

## Required sub-skills

- `browse` (already available) — for reading Apple Developer docs when SwiftUI API details are unclear.
- Swift Testing (`import Testing`) for unit tests, `pointfreeco/swift-snapshot-testing` for view snapshots.

## Work procedure

1. **Read context** (always do these in parallel on first tool turn):
   - `/Users/ruben/Developer/gitruben/kite/.factory/missions/kite-v1/mission.md`
   - `/Users/ruben/Developer/gitruben/kite/.factory/missions/kite-v1/AGENTS.md`
   - `/Users/ruben/Developer/gitruben/kite/.factory/missions/kite-v1/INTERFACES.md`
   - `/Users/ruben/Developer/gitruben/kite/.factory/missions/kite-v1/library/swiftui-macos.md`
   - `/Users/ruben/Developer/gitruben/kite/.factory/missions/kite-v1/validation-contract.md` — read the VAL-IDs this feature fulfills.
   - The feature's entry in `features.json`.

2. **Verify preconditions are really done**: every precondition feature ID in `features.json` must have a corresponding commit on the current branch (git log --oneline). If not, return `BLOCKED:` to orchestrator.

3. **Plan in one paragraph**: before writing code, summarize in one paragraph what files you'll touch and in what order. Keep it short; no multi-page plans.

4. **Write tests first (RED)**: for every assertion in the feature's `fulfills` list, write or update a test that would currently fail. For view snapshots, set `isRecording = false` — new references must be reviewed.

5. **Implement (GREEN)**: write production code to make tests pass. Follow `AGENTS.md` conventions (Swift style, naming, file layout). Prefer `@Observable` over `ObservableObject`. Prefer `async/await` over Combine. Prefer SwiftUI over AppKit — drop to AppKit only if a SwiftUI feature is missing.

6. **Do not modify files owned by `git-engine-worker`** (see INTERFACES.md §3). If you need a new method on `Git`, a new parser field, or a new model property, return to orchestrator with a `discoveredIssues` entry.

7. **Run the validation gate** (INTERFACES.md §5): `xcodebuild build`, `xcodebuild test` or `swift test`, `swiftformat --lint`, `swiftlint --strict`. All must exit 0.

8. **Manual verification** per the feature's `verificationSteps`. For UI features, launch the app and confirm the feature works end-to-end against at least one fixture repo. If you cannot launch the app in your environment (no display), say so explicitly in the handoff — do not claim pass.

9. **Commit once**: one commit per feature, message `<featureId>: <short description>` with a body listing the fulfilled VAL-IDs. No `--no-verify`, no `--amend` across features.

10. **Produce handoff JSON** (INTERFACES.md §1) and return to orchestrator.

## Example handoff

```json
{
  "featureId": "M2-repo-sidebar",
  "salientSummary": "Sidebar lists repos from RepoScanner with pinned/scanned sections, ContentUnavailableView empty state, last-selected restoration; 6 unit tests + 3 snapshot tests green; VAL-REPO-007/008/009 and VAL-UI-007/010 fulfilled.",
  "whatWasImplemented": "Added Sources/Views/Sidebar/RepoSidebarView.swift (NavigationSplitView leftmost column with List + collapsible Sections), Sources/ViewModels/RepoSidebarModel.swift (@Observable wrapper around RepoScanner + PinStore), Sources/Views/Sidebar/EmptyRepoList.swift (ContentUnavailableView + 'Add folder…' button opening Settings). Last-selected repo restored via M1-persistence. Three snapshot references committed for light, dark, empty states.",
  "whatWasLeftUndone": "",
  "verification": {
    "commandsRun": [
      { "command": "xcodebuild -scheme Kite -configuration Debug build", "exitCode": 0, "observation": "BUILD SUCCEEDED" },
      { "command": "xcodebuild test -scheme Kite -only-testing KiteUITests/RepoSidebarTests", "exitCode": 0, "observation": "5 of 5 tests passed" },
      { "command": "swiftformat --lint Sources Tests", "exitCode": 0, "observation": "no violations" },
      { "command": "swiftlint --strict", "exitCode": 0, "observation": "0 warnings" }
    ],
    "interactiveChecks": [
      { "action": "Launched Kite with a fixture ~/tmp-roots containing two repos; clicked each; then quit and relaunched", "observed": "Both repos visible in sidebar; click selected each in turn; after relaunch, the last-clicked repo was re-selected" }
    ]
  },
  "tests": {
    "added": [
      {
        "file": "Tests/KiteUITests/RepoSidebarTests.swift",
        "cases": [
          { "name": "testSidebarListsDiscoveredRepos", "verifies": "VAL-REPO-001" },
          { "name": "testSelectingRepoUpdatesDetailPaneWithin500ms", "verifies": "VAL-REPO-007" },
          { "name": "testLastSelectedRepoRestoredOnRelaunch", "verifies": "VAL-REPO-008" },
          { "name": "testPinnedReposAppearInPinnedSection", "verifies": "VAL-REPO-009" },
          { "name": "testEmptyStateShowsAddFolderButton", "verifies": "VAL-UI-007" }
        ]
      },
      {
        "file": "Tests/ViewTests/RepoSidebarSnapshotTests.swift",
        "cases": [
          { "name": "testLightMode", "verifies": "VAL-UI-010" },
          { "name": "testDarkMode", "verifies": "VAL-UI-010" },
          { "name": "testEmptyState", "verifies": "VAL-UI-007" }
        ]
      }
    ]
  },
  "discoveredIssues": []
}
```

## Established patterns to reuse

- **Monotonic-tick auto-dismiss** for transient UI states (inline errors, toasts): `@State var tick: Int = 0; @State var error: String? = nil`. On trigger: `tick += 1; let mine = tick; error = msg; Task { try? await Task.sleep(for: .seconds(5)); if mine == tick { error = nil } }`. Race-free under rapid retriggers. Pattern precedent: `SettingsRootsTab.showInlineError`.
- **App-level state injection:** cross-referenced `@State` models on the `@main App` struct + `.environment(...)` on the root view + `@Environment(Type.self)` in consumers. Precedent: `KiteApp` → `PersistenceStore`/`RepoSidebarModel`.
- **Fixture-seed launch args:** any `-KITE_FIXTURE_*` CLI flag that mutates persistence MUST gate on `ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil`. Otherwise a developer accidentally passing the flag poisons real prefs.
- **Snapshot testing discipline:** verify `md5` of all recorded PNGs differ before sign-off. Identical bytes = false green. Wrap `NSHostingController` targets with `.background(Color(nsColor: .windowBackgroundColor))` to force real rendering; snapshot row views individually instead of whole `List`/`Table`.

## When to return to orchestrator

- Precondition feature's handoff says "done" but code isn't actually committed.
- You need a new method/field on a `git-engine-worker`-owned type.
- Validation gate command fails for a non-code reason (missing Xcode, missing SwiftLint, etc.).
- You discover an assertion in `validation-contract.md` that is impossible to fulfill as written (e.g. requires a feature not in scope).
- You're tempted to disable a SwiftLint rule — ask first, don't silently `// swiftlint:disable`.
- You're tempted to lower an XCUITest timeout because a test is flaky — investigate instead.
- The feature description in `features.json` contradicts the validation contract.

## Never mark complete if

- Any test added in this feature is failing or skipped.
- `xcodebuild build` produces warnings (treat as errors in Release scheme).
- A snapshot test diff exists that you haven't reviewed visually.
- The feature touched `Sources/Git/**` or `Sources/Repo/**` (those are `git-engine-worker` territory).
- You could not manually verify UI behavior (e.g. no display available) AND the feature is UI-visible. Say so explicitly; do not claim pass.
- Any `--force` / `reset --hard` / `clean` / `stash` / `commit` / `merge` / `rebase` appeared in code you wrote.
