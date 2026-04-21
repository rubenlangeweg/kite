# Resume Kite mission

Checkpoint — say `resume` to continue.

## Where we are
- **7/8 milestones with features landed.** M1 foundation · M2 repo-list · M3 branch-list · M4 graph · M5 net-ops · M6 branch-ops · M7 diff (code-complete, test debt).
- Scrutiny: M1–M6 PASS-with-non-blocking, M7 scrutiny pending.
- **Latest HEAD:** last commit is `M7-commit-diff: selected-commit diff pane with header + file diffs (tests pending)`.
- **Tests:** all currently-authored suites green under the skip-list (build SUCCEEDED, 48+ XCTest + ~230 Swift Testing).
- **Test debt:** M7-commit-diff has no ViewModel / snapshot / XCUI tests yet — worker hit rate limit before authoring them. **See "Next on resume" for the plan.**

## What's working now (open Kite.xcodeproj → ⌘R)

- Sidebar, Settings → Roots, pin/unpin
- Status header + branch list + graph (200 commits, lane colors, pills)
- **Fetch / Pull / Push toolbar buttons** with progress, toasts, auto-fetch every 5 min
- **Create branch** sheet + double-click switch (local + remote)
- **Uncommitted diff** on the right pane by default
- **🆕 Commit diff on the right pane when you click a commit in the graph** (header with subject/author/date/refs + full `git show` patch)
- All read-only; no force-push in source (grep-proven); FSEvents auto-refresh everywhere

## Next on resume

1. **`M7-fix-commit-diff-tests`** (small, targeted) — author the 3 test files + handoff JSON. The worker brief is already in prior conversation; essentially: real-fixture ViewModel tests, in-memory snapshot tests, XCUITest stubs.
2. **`scrutiny-validator-diff`** — full M7 milestone review. Expect non-blocker findings about: RepoDetailModel consolidation (now at 4 FS observers, M7-commit-diff added a 5th via `.task(id: sha)` but that's NOT FS-driven), dark-mode snapshot discipline, classifier edge cases.
3. **M8 polish** (3 features + 1 fix):
   - `M8-commands-and-menu` — wire ⌘R/⌘⇧F/⌘⇧P/⌘⇧K/⌘N/⌘⇧N/⌘T shortcuts + App menu items
   - `M8-app-icon-and-plist` — real `.icns`, About window, final Info.plist sweep
   - `M8-release-packaging` — Release xcodebuild, <20MB bundle, Sign to Run Locally install recipe
   - `M8-fix-snapshot-degeneracy` — rebuild the 2 skipped snapshot suites with darkAqua discipline
4. **Scrutiny-validator-polish** + full-suite validation + mission complete.

## Remaining fix features

- `M8-fix-snapshot-degeneracy` — RepoSidebar + SettingsRootsTab references currently on the `-skip-testing:` list
- `M1-fix-progress-consume-all` — optional; smoother M5 fetch progress
- Optional `M7-preq-repo-detail-model` consolidation — deferrable; GitQueue still bounds the damage

## Patterns (AGENTS.md + SKILL.md)

- App-level `@State` models → `.environment(...)` on both WindowGroup AND Settings
- `GitQueue.CompletionGate` serialization across `await`
- Stateful outer + pure Content inner view split
- Monotonic-tick auto-dismiss
- `@Bindable var model = model` + `$model.selection` for List bindings
- XCTest-gated fixture launch args
- Snapshot md5-distinct; force `.darkAqua` via `NSHostingController.view.appearance`
- Subprocess fan-out concurrent inside ONE `queue.run`
- `NetworkOps.runStreaming` shared template for fetch/pull/push
- FSEvents-driven observer refresh; `.task(id: <stable>)` for selection-driven reloads
- `Git.run` now drains pipes concurrently (M1-fix-git-run-drain) — safe for any output size

Resume pointer: orchestrator should spawn `M7-fix-commit-diff-tests`, then `scrutiny-validator-diff`, then M8.
