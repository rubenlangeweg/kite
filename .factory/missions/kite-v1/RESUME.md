# Kite v1 — SHIPPED

Mission complete. This file is archival.

## Final state
- All 8 milestones complete (foundation, repo-list, branch-list, graph, net-ops, branch-ops, diff, polish).
- 253 tests green under the 13-entry snapshot skip-list.
- Release build: 6.3 MB `Kite.app`, ad-hoc signed, universal (x86_64 + arm64).
- Final scrutiny: PASS-with-non-blocking. Zero blockers.

## Install + run

```bash
cd ~/Developer/gitruben/kite
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
scripts/build_release.sh
open build/Build/Products/Release/
# Drag Kite.app into /Applications, then right-click → Open on first launch.
```

Or for development:

```bash
xcodegen generate
open Kite.xcodeproj   # ⌘R
```

## v2 backlog (in priority order)

1. `M8-fix-snapshot-degeneracy` — rebuild 13 drifted snapshot suites with deterministic NSAppearance + windowBackgroundColor + fixed-frame discipline on a pinned runner.
2. `M7-preq-repo-detail-model` — consolidate 4 FS observers (branch list, status header, graph, uncommitted-diff) into one shared `RepoDetailModel`.
3. ⌘T switch-branch — add a command-palette-style branch picker.
4. ErrorClassifier pattern ordering — check `notAGitRepository` before `auth`.
5. `SecurityInvariantsTests` short-form flag coverage — test `-f` / `-D` variants too.
6. `scripts/` ownership in INTERFACES.md §3.
7. `splitShowOutput` boundary tightening — `\n\ndiff --git` instead of `\ndiff --git`.
8. `ForEach id` stability — path-based instead of offset-based.
9. Push-noUpstream flow from keyboard shortcut (currently only works via toolbar button's sheet).
10. XCUITest host TCC unblock — grant Xcode Automation + Accessibility, then the 23 pending XCUITests can run and convert to live evidence.

## Patterns locked in (don't regress in v2)

- `@main App` @State → `.environment(...)` → `@Environment(Type.self)`
- `GitQueue.CompletionGate` serialization across `await`
- Stateful outer view + pure `…Content` inner view for snapshot-friendliness
- Monotonic-tick auto-dismiss for transient UI states
- `@Bindable var model = model` + `$model.selection` for List
- XCTest-gated fixture launch args (`XCTestConfigurationFilePath`)
- Subprocess fan-out: `async let` inside ONE `focus.queue.run`
- `NetworkOps.runStreaming` shared template
- FSEvents-driven observer refresh (no callback plumbing)
- `Git.run` concurrent pipe drain via `readabilityHandler`
- `ByteAccumulator` lock-guarded class (not actor) when the terminationHandler can't await

Fly it. 🪁
