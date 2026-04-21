# Resume Kite mission

Checkpoint — say `resume` to continue.

## Where we are
- **6/8 milestones complete**: M1 foundation · M2 repo-list · M3 branch-list · M4 graph · M5 net-ops · M6 branch-ops.
- **219 Swift Testing tests + snapshots green** under the skip-list.
- **~33 commits** on `main`.
- Latest HEAD: `10305ec M6-switch-branch`.
- Scrutiny status: M1–M5 all PASS-with-non-blocking; **M6 scrutiny pending** (small milestone — reused M5 patterns, no new architecture).
- **Next on resume:** M6 scrutiny (quick), then `M1-fix-git-run-drain` (pre-req), then M7 diff (2 features), M7 scrutiny, M8 polish (3 features + fix-snapshot-degeneracy), M8 scrutiny.

## What you can try NOW

```bash
cd /Users/ruben/Developer/gitruben/kite
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
open Kite.xcodeproj   # ⌘R
```

**New since last checkpoint:**
- **Toolbar: Fetch / Pull / Push / New-branch buttons** with progress indicator. All serialized per repo. No force-push anywhere in source (grep-test proves VAL-SEC-001/002/003).
- **Toasts**: success (auto-dismiss 5s), error (sticky with click-to-expand full stderr).
- **Push auto-upstream prompt**: pushing a branch without upstream shows a sheet offering `git push -u`.
- **Auto-fetch** every 5 minutes on focused repo only (toggle in Settings → General).
- **Double-click a branch row** to switch. Double-click a remote branch to create a tracking local. Dirty tree → toast "stash or commit in terminal".
- **⌘+click or toolbar button for New Branch** (keyboard shortcut ⌘⇧N comes in M8).

You now have a real GitKraken replacement for daily basic flows.

## Remaining work (9 features left + fixes)

| | Features | Notes |
|---|---|---|
| M7 diff | 2 | Uncommitted diff + commit diff. **Blocked by `M1-fix-git-run-drain`** (>64KB outputs would deadlock). |
| M8 polish | 3 | Commands/menu with keyboard shortcuts, app icon + Info.plist, Release packaging. |
| fix-features | 3+ | `M1-fix-git-run-drain` (pre-M7), `M1-fix-progress-multi-events` (optional polish), `M8-fix-snapshot-degeneracy` (rebuild broken snapshot suites), optional `RepoDetailModel` consolidation before M7 to keep fan-out ≤ 4. |

Per-milestone scrutiny + deferred XCUITest runs (TCC-gated).

## Fix features queued

- `M1-fix-git-run-drain` — refactor `Git.run` to drain both pipes concurrently via `readabilityHandler`. Required before M7 (git show/diff routinely >64KB).
- `M1-fix-progress-multi-events` — optional; smoother progress from ProgressParser (return array per chunk instead of last-only).
- `M8-fix-snapshot-degeneracy` — rebuild `RepoSidebarSnapshotTests` + `SettingsRootsTabSnapshotTests` with proper `.darkAqua` + `.background` discipline. Currently on the `-skip-testing:` list.
- `M7-preq-repo-detail-model` — optional; consolidate the now-4-or-5-per-focus observers into one `RepoDetailModel` before M7 ships another 2.

## Patterns established (AGENTS.md + SKILL.md)

- App-level `@State` on `@main App` → `.environment(...)` → `@Environment(Type.self)`.
- `GitQueue.CompletionGate` serialization across `await` suspensions.
- Stateful outer + pure inner view split (e.g. `StatusHeaderView` + `StatusHeaderContent`).
- Monotonic-tick auto-dismiss (Toasts, Inline errors).
- `@Bindable var model` + `$model.selection` for `List(selection:)`.
- XCTest-gated fixture launch args.
- Snapshot md5-distinct; force `.darkAqua` via `NSHostingController.view.appearance`.
- Subprocess fan-out: concurrent `async let` inside ONE `queue.run`.
- `NetworkOps.runStreaming(on:args:progressLabel:)` shared template for fetch/pull/push.
- FSEvents-driven observer refresh on `git` writes (no manual callbacks).

Resume pointer: orchestrator should run `scrutiny-validator-branch-ops` (quick), then `M1-fix-git-run-drain`, then `M7-uncommitted-diff`.
