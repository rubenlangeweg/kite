# Kite v1 — Validation Contract

> Single source of truth for "done". Every assertion below must be true before Kite v1 is signed off.
>
> **Evidence tools:**
> - `swift test` — Swift Testing unit/parser tests
> - `snapshot` — `pointfreeco/swift-snapshot-testing` reference comparisons
> - `xcuitest` — Xcode UI test harness driving the running app
> - `manual` — user walkthrough with screen recording against a golden script
> - `shell` — real-git shell command producing an expected observable state

---

## VAL-REPO — Repository discovery & sidebar

### VAL-REPO-001: Auto-scan discovers repos under `~/Developer` depth-1
On launch (with no extra roots configured), the sidebar lists every directory at `~/Developer/*/` that contains a `.git/` directory. Directories without `.git/` are not listed. Scan completes in <200ms for a directory containing ≤100 entries.
**Tool:** `xcuitest` — assert sidebar row count equals output of `find ~/Developer -maxdepth 2 -name .git -type d | wc -l`.
**Evidence:** `KiteUITests/RepoScanTests.testDepth1Scan`.

### VAL-REPO-002: Non-git directories are excluded
A directory `~/Developer/not-a-repo/` containing files but no `.git/` does not appear in the sidebar.
**Tool:** `xcuitest` — create temp dir fixture, assert absent.

### VAL-REPO-003: Extra roots from Settings are scanned
After the user adds `~/rb2-work` as an extra root in Settings, repos under `~/rb2-work/*/` appear in the sidebar alongside `~/Developer` repos, grouped by root.
**Tool:** `xcuitest` — fixture with two roots; assert two sidebar sections.

### VAL-REPO-004: Removed extra roots stop being scanned
Removing a root from Settings removes its repos from the sidebar without restart.
**Tool:** `xcuitest`.

### VAL-REPO-005: Invalid extra root is surfaced, not crashed
Adding a non-existent path shows an inline error in Settings and does not crash the app.
**Tool:** `xcuitest`.

### VAL-REPO-006: Bare repos are detected and labeled
A bare repo (`git init --bare foo.git` under a root) is listed with a "bare" badge and selecting it shows a read-only panel stating "Bare repositories have no working tree."
**Tool:** `xcuitest` — fixture with bare repo.

### VAL-REPO-007: Selecting a repo loads its branches and graph within 500ms
For a 500-commit repo with ≤20 branches, clicking it in the sidebar renders both the branch list and the graph within 500ms on an M1+ Mac.
**Tool:** `xcuitest` — perf assert.

### VAL-REPO-008: Last-selected repo restored on relaunch
Quitting and relaunching re-selects the previously focused repo.
**Tool:** `xcuitest`.

### VAL-REPO-009: Pinned repos float to top of sidebar
Right-click → Pin moves a repo to a pinned section above the auto-scanned section. Unpin returns it to its natural position.
**Tool:** `xcuitest`.

### VAL-REPO-010: FSEvents refresh on external commit
With the focused repo open, running `git commit` in Terminal causes the graph and branch list to reflect the new commit within 2s, without user action.
**Tool:** `manual` — recorded.

---

## VAL-BRANCH — Branch list & status

### VAL-BRANCH-001: Local branches listed with current branch marked
All local branches (`git for-each-ref refs/heads/`) are shown. The checked-out branch has a visible "current" indicator.
**Tool:** `xcuitest`.

### VAL-BRANCH-002: Remote branches listed in a collapsible section
Branches under `refs/remotes/<remote>/` are shown grouped by remote, collapsible per remote, `HEAD` pointers (e.g. `origin/HEAD`) filtered out.
**Tool:** `xcuitest`.

### VAL-BRANCH-003: Ahead/behind counts displayed for branches with upstream
Branches whose `upstream:track` output contains `ahead N` / `behind M` display both counts. Branches with no upstream show "no upstream". Branches with `[gone]` upstream show a "gone" badge.
**Tool:** `swift test` — parser unit test + `xcuitest` view test.

### VAL-BRANCH-004: Detached HEAD surfaced as a pseudo-branch
When HEAD is detached, the branch list shows a "(detached @ <short-sha>)" pseudo-row highlighted as current.
**Tool:** `xcuitest` — fixture repo with detached HEAD.

### VAL-BRANCH-005: Working-tree status reflected in detail header
The repo detail header shows `X modified, Y staged, Z untracked` derived from `git status --porcelain=v2`.
**Tool:** `swift test` — parser test on fixture output.

### VAL-BRANCH-006: Branch list refreshes after fetch
After a successful fetch, remote branch counts (ahead/behind) update without a manual ⌘R.
**Tool:** `manual`.

---

## VAL-GRAPH — Commit DAG rendering

### VAL-GRAPH-001: Last 200 commits rendered across all refs
`git log --all --topo-order -n 200` backs the graph. Commits beyond 200 are cut off with a "200-commit limit" footer marker.
**Tool:** `swift test` + `snapshot`.

### VAL-GRAPH-002: Column-reuse lane assignment matches reference fixture
For a canonical fixture repo (checked into tests) with a known DAG, the computed `LayoutRow` sequence matches a frozen reference JSON.
**Tool:** `swift test` — `GraphLayoutTests.testFixtureRepo`.

### VAL-GRAPH-003: First-parent line stays in leftmost lane when possible
For a repo with a linear `main` and two merged feature branches, `main`'s commits all share lane 0 across the visible range.
**Tool:** `swift test`.

### VAL-GRAPH-004: Colors stable across refresh for same branch
Hashing branch name → palette index produces the same color across two fetches of identical data.
**Tool:** `swift test`.

### VAL-GRAPH-005: `main` is always blue
Regardless of hash, `main` and `master` render in the hardcoded blue slot.
**Tool:** `swift test`.

### VAL-GRAPH-006: Octopus merges render with straight-line fallback
A commit with ≥3 parents renders with straight connecting lines (no crash, no bezier) and a "octopus" tooltip.
**Tool:** `snapshot`.

### VAL-GRAPH-007: Branch pills render next to tip commits
Each commit with one or more refs pointing at it shows a labeled pill per ref. Pills overflow as `+N` beyond 3.
**Tool:** `snapshot`.

### VAL-GRAPH-008: Scroll performance 60fps with 200 commits
Smooth-scrolling the full 200-commit graph maintains ≥55 fps (Instruments, Core Animation profile) on M1 Mac.
**Tool:** `manual` — Instruments recording attached.

### VAL-GRAPH-009: Selecting a commit opens read-only diff
Clicking a commit row in the graph opens the diff viewer (`git show <sha>`) in the right pane.
**Tool:** `xcuitest`.

### VAL-GRAPH-010: Graph preserves scroll position across FSEvents refresh
After an external commit triggers a refresh, the user's scroll position within the graph is preserved.
**Tool:** `xcuitest`.

### VAL-GRAPH-011: Shallow-clone truncation indicator
If the repo is shallow (`git rev-parse --is-shallow-repository` returns true) the graph shows a "shallow clone — history truncated" banner above the list.
**Tool:** `xcuitest`.

---

## VAL-NET — Network operations (fetch / pull / push)

### VAL-NET-001: Fetch runs `git fetch --all --prune`
⌘⇧F triggers `git fetch --all --prune` in the focused repo's directory. Progress stderr parsed line-by-line drives the toolbar progress indicator.
**Tool:** `xcuitest` + `shell` assert in command log.

### VAL-NET-002: Pull uses fast-forward only
⌘⇧P runs `git pull --ff-only`. If the branch cannot fast-forward, the result is a sticky error toast with "Non-fast-forward: pull rebased or merged manually in terminal."
**Tool:** `xcuitest` — fixture with diverged history.

### VAL-NET-003: Push runs `git push` without `--force`
⌘⇧K runs `git push`. Force-push flags are never passed. Missing-upstream errors are surfaced with a "set upstream?" prompt offering to run `git push -u origin <branch>` on confirm.
**Tool:** `xcuitest`.

### VAL-NET-004: Auth failures surface as actionable toast
A push against a remote requiring auth that fails returns a sticky toast: "Authentication failed for <remote>. Check ssh-agent or credential helper." Never blocks the UI.
**Tool:** `xcuitest` — fixture with bogus remote.

### VAL-NET-005: Successful op shows auto-dismissing success toast
Successful fetch / pull / push shows a green bottom toast auto-dismissed after 5s.
**Tool:** `xcuitest`.

### VAL-NET-006: Auto-fetch every 5 min on focused repo
A timer (cancelable on repo change, window blur, or quit) fires `git fetch --all --prune` every 5 min on the focused repo. The user can disable in Settings.
**Tool:** `xcuitest` — stubbed clock.

### VAL-NET-007: Auto-fetch does not fire on non-focused repos
Switching between repos within 5 min does not queue background fetches on previously viewed repos.
**Tool:** `swift test` — timer lifecycle test.

### VAL-NET-008: `GIT_TERMINAL_PROMPT=0` prevents hangs
A repo whose remote requires interactive password input fails fast (<10s) with an auth error, never hangs.
**Tool:** `xcuitest`.

### VAL-NET-009: Per-repo GitQueue serializes ops
Triggering ⌘⇧F and ⌘⇧K in quick succession executes sequentially, not concurrently, on the same repo. Verified via command-log ordering.
**Tool:** `swift test`.

### VAL-NET-010: Cancel in-flight op via window close
Closing the main window cancels any in-flight `Process` via `terminate()`; the app does not leak `git` subprocesses (verified by `pgrep -P <kite-pid>` after close).
**Tool:** `manual`.

### VAL-NET-011: Progress parsing handles `\r`-delimited updates
Progress stderr containing `Receiving objects:  42% (840/2000)\r` updates the progress indicator percentage without spawning duplicate log rows.
**Tool:** `swift test` — parser test.

---

## VAL-BRANCHOP — Branch creation & checkout

### VAL-BRANCHOP-001: Create branch via ⌘⇧N
⌘⇧N opens a sheet prompting for branch name (validated: no spaces, no leading `-`, no reserved names). On confirm, runs `git switch -c <name>` from the current HEAD.
**Tool:** `xcuitest`.

### VAL-BRANCHOP-002: Invalid branch name blocks submission
Names matching git's ref-format rules (no `..`, no `@{`, no `~`, no `^`, no `:`, etc.) are rejected inline with a specific message.
**Tool:** `swift test` — validator unit test.

### VAL-BRANCHOP-003: Duplicate branch name surfaces error
Attempting to create a branch name that already exists surfaces a specific error toast, does not leave the repo in a weird state.
**Tool:** `xcuitest`.

### VAL-BRANCHOP-004: Double-click local branch switches to it
Double-clicking a local branch in the branch list runs `git switch <name>`. On success, the branch list's "current" indicator moves and the graph redraws.
**Tool:** `xcuitest`.

### VAL-BRANCHOP-005: Double-click remote branch creates tracking local
Double-clicking `origin/feature-x` runs `git switch -c feature-x --track origin/feature-x` (if no local exists) or offers to switch to the existing local branch if one already tracks it.
**Tool:** `xcuitest`.

### VAL-BRANCHOP-006: Dirty working tree blocks switch with clear error
If `git switch` fails with "Your local changes would be overwritten", the user sees a toast: "Uncommitted changes — stash or commit in terminal before switching." No `--force` option is offered.
**Tool:** `xcuitest`.

---

## VAL-DIFF — Diff viewer

### VAL-DIFF-001: Uncommitted diff pane renders `git diff` + `git diff --staged`
Selecting "Working copy" in the repo detail pane shows unified diff combining unstaged (top) and staged (bottom) changes, each under a file-path header.
**Tool:** `swift test` — parser + `snapshot`.

### VAL-DIFF-002: Empty working tree shows "No uncommitted changes"
A clean tree renders an empty state with SF Symbol and label.
**Tool:** `xcuitest`.

### VAL-DIFF-003: Selected commit diff renders `git show <sha>`
Selecting a commit in the graph shows its full diff (all files) with commit header (sha, author, date, subject, body).
**Tool:** `snapshot`.

### VAL-DIFF-004: Unified diff line coloring
Added lines `+` highlighted green, removed lines `-` red, context gray. Monospace font. No syntax highlighting in v1.
**Tool:** `snapshot`.

### VAL-DIFF-005: Binary files indicated, not rendered
Binary file diffs show "Binary file — not displayed" instead of gibberish.
**Tool:** `snapshot`.

### VAL-DIFF-006: Large diff (>5k lines) virtualized
A 10k-line diff scrolls at 60fps and memory stays under 200MB.
**Tool:** `manual` — Instruments.

### VAL-DIFF-007: Diff is strictly read-only
No "stage", "discard", "revert" buttons exist anywhere in v1. No right-click actions on diff lines.
**Tool:** `xcuitest`.

---

## VAL-UI — UI chrome, toasts, commands

### VAL-UI-001: Three-pane NavigationSplitView layout
Sidebar (repos) | middle (branches + graph) | right (diff). Sidebar and right pane are collapsible via toolbar toggle.
**Tool:** `xcuitest`.

### VAL-UI-002: Toolbar has refresh + fetch + pull + push + new-branch buttons
Primary toolbar shows those five actions with SF Symbols. All respect focused repo.
**Tool:** `xcuitest`.

### VAL-UI-003: Keyboard shortcut map matches spec
⌘R, ⌘⇧F, ⌘⇧P, ⌘⇧K, ⌘N, ⌘,, ⌘⇧N, ⌘T all invoke the documented command and show their binding in the menu bar.
**Tool:** `xcuitest`.

### VAL-UI-004: Toast banners appear at bottom-center
Success toasts (green, 5s auto-dismiss) and error toasts (red, sticky with ✕) render at the bottom of the window, over the content.
**Tool:** `snapshot`.

### VAL-UI-005: Error toast click opens full stderr panel
Clicking an error toast expands a detail panel showing the full captured stderr from the failing git command.
**Tool:** `xcuitest`.

### VAL-UI-006: Toolbar progress indicator during long ops
Active fetch/pull/push shows an indeterminate or determinate progress indicator in the toolbar depending on whether percentage was parseable from stderr.
**Tool:** `xcuitest`.

### VAL-UI-007: ContentUnavailableView on empty repo sidebar
With no discovered repos and no extra roots, the sidebar shows `ContentUnavailableView` with action button "Add folder…".
**Tool:** `xcuitest`.

### VAL-UI-008: Settings window reachable via ⌘,
⌘, opens a `Settings` scene with tabs: General, Roots, About.
**Tool:** `xcuitest`.

### VAL-UI-009: New window via ⌘N
⌘N opens a second main window; both reflect state independently.
**Tool:** `xcuitest`.

### VAL-UI-010: Dark mode parity
All views render correctly in Dark and Light appearance.
**Tool:** `snapshot` — both traits.

---

## VAL-PERSIST — Persistence

### VAL-PERSIST-001: Pinned repos persist across relaunch
Pinning `kite` and relaunching the app leaves it pinned.
**Tool:** `xcuitest`.

### VAL-PERSIST-002: Extra roots persist across relaunch
Roots added in Settings survive quit/relaunch.
**Tool:** `xcuitest`.

### VAL-PERSIST-003: Last-opened repo restored
Relaunch re-selects the previously focused repo (per VAL-REPO-008).
**Tool:** `xcuitest`.

### VAL-PERSIST-004: Window size + split positions restored
Resizing sidebar/detail split and quitting restores those positions on next launch.
**Tool:** `xcuitest`.

### VAL-PERSIST-005: UserDefaults schema is versioned
The persistence blob includes a schema version field; a future migration point exists in `Persistence.swift`.
**Tool:** `swift test`.

---

## VAL-PARSE — Git output parsers (unit-level)

### VAL-PARSE-001: `git branch --format` null-delimited parser
Given the documented `--format='%(refname:short)%00%(objectname)%00%(upstream:short)%00%(upstream:track)'` output, parser extracts each field correctly including empty upstream.
**Tool:** `swift test`.

### VAL-PARSE-002: `git log --all` topo-ordered parser
Given known output (fixture in tests), parser reconstructs commits with parent arrays.
**Tool:** `swift test`.

### VAL-PARSE-003: `git status --porcelain=v2 --branch -z` parser
Parser extracts branch info, ahead/behind, staged/unstaged/untracked counts.
**Tool:** `swift test`.

### VAL-PARSE-004: `git for-each-ref` ref-join parser
Parser maps commit sha → list of refs (branches local/remote), excluding `HEAD` symbolic refs.
**Tool:** `swift test`.

### VAL-PARSE-005: Unified diff parser handles no-newline-at-EOF marker
Parser correctly handles `\ No newline at end of file` without treating it as a diff line.
**Tool:** `swift test`.

### VAL-PARSE-006: Progress parser splits on `\r` and `\n`
`Receiving objects:  1% (10/1000)\rReceiving objects:  2% (20/1000)\r` produces two progress events, not one concatenated mess.
**Tool:** `swift test`.

### VAL-PARSE-007: Error classifier maps known stderr patterns
`fatal: Authentication failed` → `.auth`; `! [rejected] ... (non-fast-forward)` → `.nonFastForward`; `fatal: The current branch <x> has no upstream branch` → `.noUpstream`; etc.
**Tool:** `swift test`.

---

## VAL-SEC — Security & safety invariants

### VAL-SEC-001: No `--force` / `--force-with-lease` anywhere in code
Grep over source confirms neither flag appears in any `Process` argument list.
**Tool:** `shell` — `! grep -r 'force' kite/Sources | grep -v comment`.

### VAL-SEC-002: No `git reset --hard` anywhere in code
**Tool:** `shell` — grep.

### VAL-SEC-003: No `git clean` anywhere in code
**Tool:** `shell` — grep.

### VAL-SEC-004: All `Process` invocations use absolute path `/usr/bin/git` or resolved fallback
No `git` invocation relies on the app's inherited `PATH` search.
**Tool:** `swift test` + grep.

### VAL-SEC-005: `GIT_TERMINAL_PROMPT=0` and `GIT_OPTIONAL_LOCKS=0` set on every process
Verified in `Git.run` unit test.
**Tool:** `swift test`.

### VAL-SEC-006: No file write outside app's UserDefaults + cache container
The app does not write files under user repositories except via `git` subprocess (which is a deliberate git write). No stray log / cache / temp file under `~/Developer/*`.
**Tool:** `manual` — audit with `fs_usage`.

### VAL-SEC-007: Branch name input sanitized before passing to `git`
User-entered branch names are validated against git ref-format rules; no shell metacharacters can reach `Process` args (`Process` uses argv, not a shell, so injection is already mitigated — assert that).
**Tool:** `swift test`.

---

## VAL-PKG — Packaging & build

### VAL-PKG-001: `xcodebuild -scheme Kite -configuration Release` succeeds
A clean build produces `Kite.app` with no warnings treated as errors.
**Tool:** `shell`.

### VAL-PKG-002: App launches from Finder double-click
Moving `Kite.app` to `/Applications` and double-clicking launches without an unsigned-app Gatekeeper dialog (signed with local identity) or opens via right-click → Open on first run.
**Tool:** `manual`.

### VAL-PKG-003: App icon present and visible in Dock, Finder, About
A custom `.icns` renders at all expected sizes.
**Tool:** `manual`.

### VAL-PKG-004: `Info.plist` has required keys
`CFBundleIdentifier = nl.rb2.kite`, `CFBundleName = Kite`, `LSApplicationCategoryType = public.app-category.developer-tools`, `LSMinimumSystemVersion = 15.0`, `NSHighResolutionCapable = true`.
**Tool:** `shell` — `plutil -p`.

### VAL-PKG-005: `Kite.app` size under 20MB
Unoptimized Release build stays under 20MB.
**Tool:** `shell` — `du -sh`.

### VAL-PKG-006: No leftover `Process` on quit
After ⌘Q, no `/usr/bin/git` subprocesses remain.
**Tool:** `manual`.

---

## Coverage summary

| Area | Count |
|---|---|
| VAL-REPO | 10 |
| VAL-BRANCH | 6 |
| VAL-GRAPH | 11 |
| VAL-NET | 11 |
| VAL-BRANCHOP | 6 |
| VAL-DIFF | 7 |
| VAL-UI | 10 |
| VAL-PERSIST | 5 |
| VAL-PARSE | 7 |
| VAL-SEC | 7 |
| VAL-PKG | 6 |
| **Total** | **86** |

Every assertion is mapped to a feature in `features.json` via the `fulfills` array. No orphan assertions.
