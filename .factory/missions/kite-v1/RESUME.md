# Resume Kite mission

Checkpoint snapshot — say `resume` and the orchestrator will pick up from here.

## Where we are
- 3/8 milestones complete: **M1 foundation · M2 repo-list · M3 branch-list** (each with scrutiny passed, non-blocking only).
- HEAD: `e5b7a21` (or latest) — `branch-list: apply post-scrutiny guidance for M4 graph start`.
- **142 tests green** (123 Swift Testing + 19 XCTest snapshot).
- **15 commits** on `main` since initial.
- **Next step on resume:** start M4 graph milestone — most complex of the mission, 4 features.

## What you can try in the app right now

```bash
cd /Users/ruben/Developer/gitruben/kite
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
open Kite.xcodeproj   # ⌘R to launch
# or: open <DerivedData>/Kite-*/Build/Products/Debug/Kite.app
```

You'll see:
- **Sidebar** — pinned repos + per-root sections (scans `~/Developer` + configured extra roots). Right-click: Pin/Unpin/Show in Finder/Copy path.
- **Middle column upper:** `StatusHeader` (branch name, clean/dirty pills, ahead/behind) + `BranchList` (local branches with current indicator + ahead/behind/gone pills, collapsible remotes grouped by `origin`/etc., detached-HEAD banner). Refreshes automatically when you commit in terminal (FSEvents).
- **Middle column lower:** placeholder for the graph (M4).
- **Right column:** placeholder for diff (M7).
- **Settings (⌘,):** General (auto-fetch toggle) / Roots (add/remove extra scan folders) / About.

No fetch/pull/push yet (M5). No create/switch branches from UI yet (M6). Graph + diff placeholders (M4/M7).

## Remaining work

| Milestone | Features | Notes |
|---|---|---|
| **M4 graph** | 4 | Column-reuse DAG layout + per-row SwiftUI Canvas. Hardest visual piece. |
| M5 net-ops | 4 | Fetch/pull/push + auto-fetch + toast UX. Needs `M1-fix-git-error-push-cases` first. |
| M6 branch-ops | 2 | Create/checkout via UI. |
| M7 diff | 2 | Diff viewer. Needs `M1-fix-git-run-drain` first (>64KB outputs). |
| M8 polish | 3 | Icon, menu/commands, Release packaging. Plus `M8-fix-snapshot-degeneracy`. |

Plus per-milestone scrutiny + deferred user-testing-on-TCC-unblock.

## Fix features queued (just-in-time)

- `M1-fix-git-run-drain` — concurrent pipe drain in `Git.run`; **required before M7**.
- `M1-fix-git-error-push-cases` — add `.remoteRejected(String)`; **required before M5-pull-push**.
- `M1-fix-progress-consume-all` — optional for smoother M5 fetch progress.
- `M8-fix-snapshot-degeneracy` — retrofit `NSHostingController.view.appearance = .darkAqua` to older snapshot tests where dark/light are byte-identical (RepoSidebar + SettingsRootsTab).

## Patterns established (see AGENTS.md + SKILL.md)

- App-level state: `@State` models on `@main App` → `.environment(...)` → `@Environment(Type.self)`.
- Actor-reentrancy remedy: `GitQueue.CompletionGate` chain for serializing suspending bodies.
- Stateful outer + pure Content inner view split (exemplar: `StatusHeaderView` / `StatusHeaderContent`).
- Monotonic-tick auto-dismiss (inline errors, toasts).
- XCTest-gated fixture launch args (never poison prod prefs).
- Snapshot md5-distinct verification before commit; force `.darkAqua` via `NSHostingController.view.appearance`.
- Subprocess discipline: minimize count per UI refresh; `async let` / `TaskGroup` fan-out inside one `queue.run`.
- Observer fan-out limit: consolidate to `RepoDetailModel` before adding a 4th per-focus observer.

Resume pointer: orchestrator should start `M4-graph-layout` (precondition: `M1-git-parsers` ✅).
