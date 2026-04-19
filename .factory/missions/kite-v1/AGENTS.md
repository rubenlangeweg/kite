# Kite v1 — Agent Guidance

> Shared knowledge for every worker. Read this before starting your feature.

---

## Boundaries

### In scope for this mission

- Everything inside `/Users/ruben/Developer/gitruben/kite/`.
- Xcode project, SwiftUI app, Swift Testing tests, Swift files under `Sources/` and `Tests/`.
- Dependencies added via Swift Package Manager only (no CocoaPods, no Carthage).
- Approved external dependencies: `pointfreeco/swift-snapshot-testing` (tests only). No runtime dependencies beyond Apple SDKs in v1.

### Off-limits

- Any file outside `/Users/ruben/Developer/gitruben/kite/`.
- The user's actual git repositories under `~/Developer/*` — only `git` shell-outs touch those, and only with the exact ops listed in `mission.md` §3.
- Force push, reset --hard, clean, rebase, stash, commit, merge — these git operations must not appear in any source file (see VAL-SEC-001 through VAL-SEC-003).
- Cursor, VS Code, IDE configuration files of the user — don't write `.vscode/`, `.idea/`, etc.
- User-level files like `~/.gitconfig`, `~/.ssh/*`, Keychain — Kite reads them via `git` CLI but never writes to them.
- Any network calls that aren't a `git fetch` / `pull` / `push` via the local CLI. No telemetry, no error reporting, no update checks in v1.

## Conventions

### Swift style

- **Swift version:** 5.9+ (Xcode 16 / Swift 5.10 acceptable).
- **State:** prefer `@Observable` macro over `ObservableObject`. Use `@State`, `@Bindable`, `@Environment` as documented in `library/swiftui-macos.md` §3.
- **Async:** prefer structured concurrency (`async`/`await`, `.task`, `TaskGroup`) over callbacks or Combine. Use `withTaskCancellationHandler` to propagate cancellation to `Process.terminate()`.
- **Errors:** domain-specific error enums (`GitError`, `ScanError`, `ParseError`). No `throw NSError(...)`, no raw string throws.
- **Result types:** avoid `Result<T, E>` unless interop forces it. Prefer `throws`.
- **Force-unwraps (`!`):** only permitted in tests or when an invariant is structurally guaranteed and documented in a short comment. Default to `guard let ... else { throw }`.
- **Access control:** default `internal`; mark `public` only for testable types crossing modules. `fileprivate` and `private` liberally.
- **Comments:** default to zero. One-line comment only when the *why* is non-obvious (a git edge case, a SwiftUI quirk). Never explain *what* well-named code does.

### Naming

- Types: `UpperCamelCase`. Values: `lowerCamelCase`.
- Git command wrappers: `Git.fetch`, `Git.pull`, `Git.push`, `Git.branchList`, etc. Not `GitFetcher`, not `FetchService`.
- Views: suffix with `View` (`RepoSidebarView`, `GraphRow`, `DiffPane`). ViewModels: suffix with `Model` (`RepoModel`, `GraphViewModel`).
- Test names: `test<What>_<When>_<Then>` with Swift Testing's `@Test("description")` annotations where clearer.
- **Persistence root type is `KiteSettings`, NOT `Settings`.** SwiftUI's `Settings` scene type is imported by `Sources/App/KiteApp.swift` and collides with a bare `Settings` name. For any Settings-related view types in later features, use `SettingsRootsTab`, `SettingsGeneralTab`, `SettingsAboutTab` — never bare `SettingsView`.

### File layout

```
kite/
  Kite.xcodeproj/
  Sources/
    App/            # @main, Scene, Commands, Settings
    Git/            # Git.run, Git.stream, error types
      Parsers/      # LogParser, BranchParser, StatusParser, DiffParser, ProgressParser, ErrorClassifier
      Layout/       # Column-reuse graph layout
      Models/       # Commit, Branch, Remote, LayoutRow, RefKind, StatusSummary
    Repo/           # RepoScanner, RepoStore, FSWatcher
    Persistence/    # UserDefaults + Codable, Keys.swift
    ViewModels/     # @Observable models
    Views/          # SwiftUI views
      Sidebar/
      Detail/
      Graph/
      Diff/
      Toasts/
      Settings/
    Design/         # Palette, Typography, SymbolMap
  Tests/
    GitTests/
    GraphLayoutTests/
    ViewTests/
    KiteUITests/
  Resources/
    Assets.xcassets/
  Info.plist
  .factory/
    missions/kite-v1/
    library/
    research/
```

### Response shape rules (for ViewModels ↔ Git engine)

- Git engine returns typed models. ViewModels do the shaping for views. Views don't parse strings.
- Expensive operations (scanning, layout, log parsing) run on a background task and hop to `@MainActor` before mutating observable state.
- Cancellation is propagated: when a view's `.task(id:)` cancels, the underlying git `Process` is terminated.

## Services

### Dev build loop

- Open `kite/Kite.xcodeproj` in Xcode 16+.
- Default scheme: `Kite`. Run target: macOS 15+ (your Mac).
- `⌘B` build, `⌘R` run, `⌘U` run all tests.

### CLI build + test (for scripted validation)

**IMPORTANT — `xcode-select` is pointed at CLT, not Xcode.app.** Do NOT run `sudo xcode-select` (not authorized). Use the `DEVELOPER_DIR` env variable to override per-invocation:

```bash
cd /Users/ruben/Developer/gitruben/kite
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -scheme Kite -configuration Debug build
xcodebuild -scheme Kite -configuration Debug test -destination 'platform=macOS'
swiftformat Sources Tests --lint   # NOTE: paths BEFORE --lint flag in swiftformat ≥0.61
swiftlint --strict
```

Every worker must `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` before any `xcodebuild` invocation. Failing to do so yields "tool 'xcodebuild' requires Xcode".

### Xcode project is generated via xcodegen

The `Kite.xcodeproj` bundle is NOT checked into git. Instead, `project.yml` (xcodegen spec) is the source of truth. Regenerate with:

```bash
xcodegen generate
```

Add `Kite.xcodeproj/` to `.gitignore`. Any change to build settings, schemes, sources, or resources goes through `project.yml`. Workers touching build configuration modify `project.yml` and re-run `xcodegen generate`.

### Installed dev tools
- Xcode 26.4.1 at `/Applications/Xcode.app`
- `xcodegen` 2.45.4
- `swiftformat` 0.61.0
- `swiftlint` 0.63.2
- `swift` 6.2.4 (via CLT)
- `git` 2.50.1 at `/usr/bin/git`

### Healthcheck

The running app has no HTTP endpoint. Healthcheck is:

1. `pgrep Kite` returns a PID.
2. The app's main window is responsive (XCUITest can focus it).

### Git CLI dependency

- Required: `/usr/bin/git` version ≥ 2.40.
- Verify at app startup; display a fatal error if missing.
- Xcode Command Line Tools may route `/usr/bin/git` through a shim — use `git --exec-path` to verify real git is callable.

## Testing guidance

- **Unit tests (`Tests/GitTests`)** — Swift Testing. Each parser tested with at least 3 fixtures: happy path, empty output, pathological edge case (binary files, newlines in commit messages, unicode branch names).
- **Layout tests (`Tests/GraphLayoutTests`)** — a canonical fixture repo (created under `Tests/GraphLayoutTests/Fixtures/`) with a pre-computed reference `LayoutRow` JSON. Any layout change that breaks the reference requires an explicit reference-JSON update (reviewed in scrutiny).
- **Snapshot tests (`Tests/ViewTests`)** — `pointfreeco/swift-snapshot-testing`. Capture reference images for graph row, branch pill, toast banner, diff line, settings panel. Both Dark and Light traits.
- **UI tests (`Tests/KiteUITests`)** — XCUITest driving the running app. Each UI test creates a tmp-dir fixture repo via `GitFixtureHelper`, points Kite at it via command-line launch args, exercises the UI, tears down.
- **Fixtures:** the `GitFixtureHelper` in `Tests/Support/` is the single source of truth for creating git fixtures. Use `.clean()`, `.oneCommit()`, `.diverged()`, `.withSubmodule()`, `.bare()`, `.shallow()`, `.detached()` etc.
- **No mocking of `git`.** Kite's value is correct behavior against real git. Use fixture repos.

## Known gotchas

### SwiftUI / macOS

1. **`Process.currentDirectoryURL` ENOENT** — set before launch, and handle `EPERM`/`ENOENT` gracefully. `library/swiftui-macos.md` §11.
2. **`terminationHandler` runs on a background queue** — hop to `@MainActor` before touching observable state.
3. **`#Preview` + `Process`** — gate `Process` calls behind `XCODE_RUNNING_FOR_PREVIEWS` env var to prevent Xcode previews from hanging.
4. **Sandbox off does NOT mean zero prompts** — macOS TCC still prompts for Desktop/Documents/Downloads/iCloud. Document in Settings.
5. **`NavigationSplitView` column widths** — set `navigationSplitViewColumnWidth(min:ideal:max:)` to avoid a collapsed sidebar on first launch.
6. **`@Observable` + `Equatable`** — `@Observable` doesn't auto-derive `Equatable`; if view needs to diff, manually implement.

### Git CLI

0. **`Git.run` pipe-buffer boundary (CRITICAL for M7).** `Git.run` captures stdout/stderr only after process termination via `readToEnd()`. This is safe for any git command whose combined output stays under ~64 KB (pipe-buffer size). For large-output commands — `git diff`, `git show`, `git log --patch`, `git archive` — use `Git.stream` instead, or refactor `Git.run` to drain both pipes concurrently via `readabilityHandler`. **Do NOT assume `Git.run` scales to diff-sized outputs.** Tracked as a pre-M7 fix feature.

1. **`git log --all --topo-order` with `-n 200` truncates BEFORE topo-ordering** — confirmed in `library/git-cli-integration.md` §4. Use `--date-order` if 200-commit selection needs to follow wall clock. We accept topo for v1 (more stable DAG).
2. **Null-delimited parsers** — always use `-z` flag when available, and split on `\0`, never on `\n`. Branch names can contain printable unicode and path separators in pathological cases.
3. **`git pull --ff-only` exit codes** — exit 128 for non-FF, exit 1 for merge conflicts (shouldn't happen with `--ff-only` but document).
4. **SSH_AUTH_SOCK** — if the app is launched from Finder (not Terminal), it inherits launchd's env, not the Terminal's. The user's ssh-agent socket is usually still found, but document if we see failures.
5. **Keychain credential helper** — `git config --get credential.helper` should return `osxkeychain` or `!/usr/bin/env git credential-manager` on a typical Mac. If neither, auth will fail for HTTPS remotes; surface as an error.
6. **Per-repo GitQueue** — two concurrent ops on the same `.git/` dir can corrupt index locks. Serialize by repo path via an actor.
7. **`git switch` vs `git checkout`** — prefer `switch`; `checkout` has overloaded semantics. Use `switch -c` to create, `switch -c <local> --track <remote>` to create-tracking.

### Graph rendering

1. **SwiftUI `Canvas` in `List` row** — re-renders on every row recycle. Keep per-row draws under ~2ms. See `library/git-graph-rendering.md` §4.
2. **Color stability** — name-hash must be deterministic across runs; use FNV-1a or similar, not `Swift.hash` (which is randomized per process).
3. **`main` hardcoded color** — special-case `main`, `master`, `trunk`, `default` to the blue slot.

### App packaging

1. **Sign to Run Locally + rebuild** — macOS TCC grants are invalidated on a rebuild that changes the app bundle's signing info. Re-grant prompts for Developer folder access may reappear; this is expected.
2. **App icon not showing in Finder** — `lsregister -f /path/to/Kite.app` refreshes the Launch Services cache.
3. **Bundle ID** — `nl.rb2.kite`. Do not change after shipping v1.

## Observability during development

- `os.Logger` with subsystems `git`, `repo`, `ui`, `persist`, `layout`. Log level `.debug` for internals, `.info` for user-visible ops, `.error` for failures.
- **Never silently swallow errors.** When a feature must continue past a failure (corrupt UserDefaults, failed JSON encode, missing FS parent, unparseable git output, etc.), log it via `Logger(subsystem: "nl.rb2.kite", category: <area>).error(...)` so the failure is observable in Console.app. A silent `catch { }` is never acceptable; `catch { logger.error(...) }` is.
- No crash reporting in v1. If Kite crashes, macOS writes a crash log under `~/Library/Logs/DiagnosticReports/Kite-*` which we inspect manually.

## Definition of Done (per feature)

A feature is NOT done until:

1. All validation gate commands (INTERFACES.md §5) exit 0.
2. Every assertion in the feature's `fulfills` array passes.
3. Handoff JSON (INTERFACES.md §1) is complete and accurate.
4. A single commit with the feature ID is on the current branch.
5. Any `discoveredIssues` entries are routed to the orchestrator.
