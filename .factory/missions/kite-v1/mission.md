# Mission: Kite v1

> Native macOS git client to replace GitKraken for daily basic-flow work.

**Owner:** Ruben (ruben@rb2.nl)
**Mission slug:** `kite-v1`
**Status:** Shaped — awaiting sign-off
**Shaped on:** 2026-04-19

---

## 1. Goal

Ship a native macOS SwiftUI app named **Kite** that lets Ruben fetch, pull, push, create branches, and check out branches across the repositories in `~/Developer`, with a GitKraken-style multi-repo dashboard and a real commit-graph visualization. The app must feel like a Mac app (SF Symbols, NavigationSplitView, toolbar) and must not cost a subscription.

## 2. Why

- Ruben currently uses GitKraken for repo overview, branch management, and basic VCS operations. He wants to drop the subscription.
- His daily flows are narrow (pull/fetch/push/create branch/checkout/overview) — a dedicated personal app is reasonable scope.
- Terminal and IDE cover every other git workflow he has (commit, merge, stash, conflict resolution). Kite doesn't need to.

## 3. Scope

### In scope (v1)

- macOS SwiftUI app packaged as `Kite.app`, "Sign to Run Locally" (personal signing identity), sandbox disabled.
- Multi-repo dashboard in a `NavigationSplitView` sidebar, auto-discovering repos under `~/Developer` (depth-1) plus user-added extra root paths.
- Per-repo detail pane with:
  - Local + remote branch list with ahead/behind counts
  - Commit DAG of last 200 commits (column-reuse lane layout, first-parent preference, branch pills, name-hash colors with `main` hardcoded blue)
  - Read-only unified diff for uncommitted changes (`git diff` + `git diff --staged`) and any selected commit (`git show`)
- Operations (triggered from toolbar / context menus / keyboard shortcuts):
  - Fetch (`git fetch --all --prune`)
  - Pull fast-forward (`git pull --ff-only`)
  - Push (`git push`; never `--force`)
  - Create branch + switch to it (`git switch -c`)
  - Checkout existing local/remote branch (`git switch`; for remote branches, `git switch -c <local> --track <remote>`)
- Auto-refresh via FSEvents on the focused repo's `.git/` directory.
- Background auto-fetch every 5 min on the **focused** repo only.
- Toast-style progress and error banners at the bottom of the window; click-to-expand full git stderr for errors.
- Persistence via `UserDefaults` + Codable: pinned repos, extra root paths, last-opened repo, last-selected branch, window size.
- Keyboard shortcuts: ⌘R refresh, ⌘⇧F fetch, ⌘⇧P pull, ⌘⇧K push, ⌘N new window, ⌘, settings, ⌘⇧N new branch, ⌘T switch branch.
- App icon (single `.icns`, SF-Symbol-inspired).

### Explicitly out of scope (deferred to v2+)

- Committing, staging, amending, interactive rebase
- Merge / rebase / cherry-pick from the UI
- Stash
- Conflict resolution UI
- Force push (`--force`, `--force-with-lease`) — terminal-only
- Remote management (add/edit/remove remotes)
- Submodules
- Worktrees beyond basic detection
- Tag pills in the graph (branches only in v1)
- Syntax highlighting in diff viewer
- Side-by-side diff
- Cross-repo background fetch / sidebar unread badges
- Signed commits, GPG, SSH key management UI
- Notarization, App Store, any distribution workflow

### Explicitly deferred decisions

- Whether Kite eventually grows into a shippable product (decided at end of v1).
- Any App Store or Developer ID signing.

## 4. Decisions (locked)

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Tech stack | SwiftUI (macOS native) | Small binary, native feel, SF Symbols, no Electron |
| 2 | Git engine | Shell out to `/usr/bin/git` | Inherits user's config, SSH agent, keychain, credential helper for free |
| 3 | v1 write ops | Fetch/pull-ff/push/branch/checkout only | Tight scope; commits/merges/stash stay in IDE |
| 4 | Repo-list UX | Multi-repo sidebar (auto-scan + extras) | Matches the "overview" GitKraken usage |
| 5 | Graph style | Full DAG, last 200 commits | Nice visualization, bounded cost |
| 6 | App name | **Kite** | Short, non-directory, easy to search/icon |
| 7 | Window model | Single main window + ⌘N for second | Simple; avoids per-repo window management |
| 8 | Repo discovery | `~/Developer` depth-1 + user-added roots via Settings | Fast default, extensible |
| 9 | Refresh model | FSEvents on focused repo + 5-min auto-fetch on focused repo only | Real-time local, cheap network |
| 10 | Diff viewer | Unified, read-only, uncommitted + commit-view | Nice-enough without TreeSitter work |
| 11 | Force push | Not in UI | Dangerous + rare; terminal covers it |
| 12 | Error/progress UX | Toast banners + toolbar progress bar | Non-blocking; click-to-expand stderr |
| 13 | Persistence | UserDefaults + Codable | SwiftData overkill for this size |
| 14 | Sandbox | Disabled | Personal tool; needs arbitrary FS read + `Process` |
| 15 | Signing | Sign to Run Locally | No Apple Developer account |
| 16 | Graph layout | Column-reuse with first-parent preference | Recommended in research (§1 of graph artifact) |
| 17 | Graph colors | Name-hash → 6-color palette, `main` hardcoded blue | Stable across refresh, readable |
| 18 | Graph edges | 3-segment straight/diagonal (no bezier) in v1 | Simpler; polish in v2 |
| 19 | Swift testing framework | Swift Testing (`#expect`) + snapshot tests | Modern default |
| 20 | Min macOS target | macOS 15 (Sequoia) | Matches `@Observable`, `@Entry`, modern APIs |

## 5. Blast radius

Greenfield project. No existing code to refactor. All changes land inside `/Users/ruben/Developer/gitruben/kite/`. Kite is read-heavy against other repos under `~/Developer` (git commands invoked with `-C <path>`), but **only write operations** it performs are `fetch/pull/push/branch/switch` in those repos — same as the user running them by hand.

Risk surface:

- **Accidental writes in user repos** — mitigated by the "no force push, no commit, no merge, no stash" scope. The only write ops are branch creation (new ref only, no destructive overwrite) and switch (safe unless working tree is dirty; we surface errors, never `--discard-changes`).
- **Runaway `Process` children** — mitigated by async cancellation (`process.terminate()` on task cancel) and `GIT_TERMINAL_PROMPT=0` to prevent credential prompts from hanging.
- **Repo scan perf on deep trees** — depth-1 default keeps scan under 100ms for `~/Developer`; prune list (node_modules, .build, DerivedData, Pods) if depth is ever raised.
- **macOS permission prompts** — disabling sandbox sidesteps TCC prompts for the Developer folder; the app may still get prompted for protected locations if Ruben adds a root under Documents/Desktop/iCloud Drive (documented in settings).

## 6. Milestones

| # | Milestone | Theme | Features |
|---|-----------|-------|----------|
| M1 | `foundation` | Scaffold, git engine, FS watcher, persistence | 5 |
| M2 | `repo-list` | Multi-repo discovery + sidebar UI | 3 |
| M3 | `branch-list` | Branch list with ahead/behind + status pane | 3 |
| M4 | `graph` | Commit DAG layout + rendering | 4 |
| M5 | `net-ops` | Fetch / pull / push + auto-fetch + toast UX | 4 |
| M6 | `branch-ops` | Create + checkout branches | 2 |
| M7 | `diff` | Uncommitted + commit diff viewer | 2 |
| M8 | `polish` | App icon, menu, settings, keyboard shortcuts, packaging | 3 |

Each milestone ends with `scrutiny-validator-<milestone>` (code review + automated tests) and `user-testing-validator-<milestone>` (end-to-end contract verification) features, auto-injected during execution.

## 7. Risks & open questions

- **Swift expertise ramp-up** — Ruben is experienced full-stack but new to SwiftUI. Workers should over-explain Swift idioms in code comments where non-obvious, and prefer standard SwiftUI patterns over clever ones. (Noted in `AGENTS.md`.)
- **Graph layout edge cases** — octopus merges, shallow-clone truncation, force-pushed orphan commits can produce weird layouts with 200-commit window. Documented in `library/git-graph-rendering.md` §9. Acceptable for v1.
- **FSEvents latency** — 500ms coalescing could miss a very fast `git commit && git commit` pair. Acceptable; ⌘R refresh is always available.
- **Cross-origin repo locations** — if Ruben later adds a root under `~/Documents` or `~/Desktop`, macOS TCC will prompt. Documented in Settings panel copy.
- **Auto-fetch while pushing** — possible race on focused repo. Resolved by a per-repo `GitQueue` serializing all ops per repo path.

## 8. References

Research artifacts in `library/`:

- [`swiftui-macos.md`](library/swiftui-macos.md) — SwiftUI scaffolding, `@Observable`, `NavigationSplitView`, `Process` wrapper, FSEvents, UserDefaults, Canvas graph row.
- [`git-cli-integration.md`](library/git-cli-integration.md) — Porcelain v2, `-z` null-delimited parsing, `for-each-ref`, DAG data via `git log --all --topo-order`, network error taxonomy, SSH/keychain auth.
- [`git-graph-rendering.md`](library/git-graph-rendering.md) — Column-reuse lane algorithm, 3-segment edges, name-hash palette, per-row `Canvas`, v1 simplifications.
- [`mac-app-packaging.md`](library/mac-app-packaging.md) — Sign to Run Locally, sandbox-off rationale, `Process` env cleanup, `.icns` pipeline, deferred notarization path.

Also: [`INTERFACES.md`](INTERFACES.md), [`AGENTS.md`](AGENTS.md), [`validation-contract.md`](validation-contract.md), [`features.json`](features.json).
