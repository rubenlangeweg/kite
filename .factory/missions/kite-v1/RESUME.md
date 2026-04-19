# Resume Kite mission

Checkpoint — say `resume` to continue.

## Where we are
- **4/8 milestones complete** + scrutiny (all PASS-with-non-blocking): M1 foundation · M2 repo-list · M3 branch-list · M4 graph.
- **195 tests green** (164 Swift Testing + 31 XCTest snapshot, under the skip-list — see `AGENTS.md` for the `-skip-testing:` flags).
- **24 commits** on `main`.
- Latest HEAD: `a8560c5 M4-graph-scroll-container`.
- **Next on resume:** before M5-pull-push, run the tiny `M1-fix-git-error-push-cases` to add `.remoteRejected(String)` / `.hookRejected(String)` / `.protectedBranch(String)` to `GitError`. Then M5 proper (4 features: toast-infrastructure → fetch → pull-push → auto-fetch).

## What you can try NOW (M4 is visually huge)

```bash
cd /Users/ruben/Developer/gitruben/kite
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
open Kite.xcodeproj   # ⌘R
```

Working features:
- **Sidebar:** repo list + pins + per-root sections + Settings→Roots flow.
- **Middle column top:** status header (branch + dirty pills + ahead/behind) + branch list (current indicator, ahead/behind, gone pills, detached-HEAD banner).
- **Middle column bottom:** 🎉 **commit DAG graph** — last 200 commits, column-reuse lane layout with first-parent preference, 6-color palette (`main`/`master`/`trunk`/`default`/`develop` → blue), branch pills with HEAD/+N overflow, relative ages, tap a commit to select it (diff pane lights up in M7). Shallow-clone banner + 200-commit-limit footer work.
- **Right column:** still placeholder for diff (M7).
- Auto-refresh on external `git commit` via FSEvents.

## Remaining work

| Milestone | Features | Notes |
|---|---|---|
| **M5 net-ops** | 4 (+ 1 pre-req) | toast infra → fetch → pull/push (needs `M1-fix-git-error-push-cases`) → auto-fetch. First write ops! |
| M6 branch-ops | 2 | Create branch (⌘⇧N), double-click to switch. |
| M7 diff | 2 | Unified diff viewer. **Blocked by `M1-fix-git-run-drain`** (concurrent pipe drain) AND **should consolidate observers into `RepoDetailModel`** first. |
| M8 polish | 3 + fix-features | App icon, Commands/menu, Release packaging, `M8-fix-snapshot-degeneracy`. |

## Fix features queued (JIT)

- `M1-fix-git-error-push-cases` — **required before M5-pull-push.** Tiny: add 3 `GitError` cases + classifier patterns.
- `M1-fix-git-run-drain` — required before M7. Refactor `Git.run` to drain pipes concurrently via `readabilityHandler` so >64KB outputs don't deadlock.
- `M1-fix-progress-consume-all` — optional; smoother M5 fetch progress.
- `M1-fix-progress-multi-events` — same.
- `M8-fix-snapshot-degeneracy` — rebuild `RepoSidebarSnapshotTests` and `SettingsRootsTabSnapshotTests` with proper `NSHostingController.view.appearance = .darkAqua` + `.background(Color(nsColor: .windowBackgroundColor))` so light/dark references differ and stay stable across re-records. Currently on the `-skip-testing:` list.
- `M7-preq-repo-detail-model` — consolidate `BranchListModel` / `StatusHeaderModel` / `GraphModel` FSWatcher reloads into one `RepoDetailModel` with prior-Task cancellation. Fan-out is already at 3; M7 adds 2 more.

## Patterns established (AGENTS.md + SKILL.md)

- App-level `@State` on `@main App` → `.environment(...)` → `@Environment(Type.self)`.
- Actor-reentrancy remedy: `GitQueue.CompletionGate` chain serializes across suspensions.
- **Stateful outer + pure Content inner** view split (exemplar: `StatusHeaderView`, now `GraphView`).
- Monotonic-tick auto-dismiss for transient UI states.
- XCTest-gated fixture launch args.
- Snapshot md5-distinct discipline; force `.darkAqua` via `NSHostingController.view.appearance`.
- Subprocess discipline: minimize per refresh; `async let` / `TaskGroup` fan-out **inside** one `queue.run`.
- Observer fan-out limit: consolidate into `RepoDetailModel` before M7.

Resume pointer: start with `M1-fix-git-error-push-cases`, then `M5-toast-infrastructure`.
