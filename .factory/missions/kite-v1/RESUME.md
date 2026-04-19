# Resume Kite mission

Checkpoint snapshot — say `resume` and the orchestrator will pick up from here.

## Where we are
- Branch `main`, HEAD `b8ba30d M2-settings-roots`.
- **Completed:** M1 foundation (5/5 features + scrutiny) + M2 repo-list features (3/3, scrutiny pending).
- **Tests green:** 107 (98 Swift Testing + 9 XCTest snapshot).
- **Next step on resume:** run scrutiny review for milestone `repo-list`, then start M3 branch-list.

## What to try in the app before resuming

```bash
cd /Users/ruben/Developer/gitruben/kite
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
open Kite.xcodeproj
```

Then ⌘R in Xcode. You'll get:
- Three-pane `NavigationSplitView` window (sidebar | content | detail).
- Sidebar lists repos auto-discovered under `~/Developer` (plus any extra roots).
- Right-click a repo: Pin / Unpin / Show in Finder / Copy path.
- ⌘, opens Settings (General / Roots / About tabs). Roots tab lets you add folders via NSOpenPanel.
- No branches, graph, diff, or git ops yet — those arrive in M3 (branch-list), M4 (graph), M5 (net-ops), M6 (branch-ops), M7 (diff).

## Unblock XCUITest (optional but recommended)
System Settings → Privacy & Security →
- **Automation** → allow Xcode
- **Accessibility** → allow Xcode

Then 9 authored XCUITests across `KiteUITests/` become runnable.

## Remaining work
| Milestone | Features | Approx LOC estimate |
|---|---|---|
| M3 branch-list | 3 | ~800 |
| M4 graph | 4 | ~1200 (graph layout + rendering is the hardest) |
| M5 net-ops | 4 | ~900 |
| M6 branch-ops | 2 | ~400 |
| M7 diff | 2 | ~600 |
| M8 polish | 3 | ~500 (icon, menu, release packaging) |

Plus per-milestone scrutiny + user-testing validators.

## Fix features queued pre-M5/M7
- `M1-fix-git-run-drain` — concurrent pipe drain in `Git.run`; required before M7 ships (git show / diff can exceed 64KB).
- `M1-fix-git-error-push-cases` — add `.remoteRejected(String)` GitError case; required before M5-pull-push.
- `M1-fix-progress-consume-all` — optional; returns array of ProgressEvent per chunk; would give M5-fetch smoother progress.

Resume pointer: orchestrator should run `scrutiny-validator-repo-list` first, then `M3-branch-list`.
