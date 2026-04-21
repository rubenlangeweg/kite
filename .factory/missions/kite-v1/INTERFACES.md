# Kite v1 — Interface Contracts

> Contracts every sub-agent (worker) must conform to. Read this before starting any feature.

---

## 1. Handoff format

Every completed feature produces a JSON handoff in the mission output log:

```json
{
  "featureId": "M1-git-engine",
  "salientSummary": "Git.run async wrapper + GitResult/GitError types; all 7 unit tests green; VAL-PARSE-007 and VAL-SEC-004/5 fulfilled.",
  "whatWasImplemented": "Added Sources/Git/Git.swift with Git.run(args:cwd:) async throws -> GitResult and Git.stream(args:cwd:) -> AsyncThrowingStream<GitEvent, Error>. Added ErrorClassifier mapping known stderr patterns to typed errors. Set GIT_TERMINAL_PROMPT=0 and GIT_OPTIONAL_LOCKS=0. Process path hardcoded to /usr/bin/git with fallback via which.",
  "whatWasLeftUndone": "Progress parser for fetch/push stderr (deferred to M5-net-ops which owns that feature).",
  "verification": {
    "commandsRun": [
      { "command": "swift test --filter GitRunTests", "exitCode": 0, "observation": "7 of 7 tests passed in 0.42s" },
      { "command": "swift test --filter ErrorClassifierTests", "exitCode": 0, "observation": "6 of 6 tests passed" }
    ],
    "interactiveChecks": []
  },
  "tests": {
    "added": [
      {
        "file": "Tests/GitTests/GitRunTests.swift",
        "cases": [
          { "name": "testRunReturnsZeroExitForValidCommand", "verifies": "VAL-PARSE-007" },
          { "name": "testRunSetsEnvironmentCorrectly", "verifies": "VAL-SEC-005" },
          { "name": "testRunUsesAbsolutePath", "verifies": "VAL-SEC-004" }
        ]
      }
    ]
  },
  "discoveredIssues": [
    { "severity": "non-blocking", "description": "Process.currentDirectoryURL throws ENOENT if the cwd was deleted between scan and run; added retry-with-rescan in GitRepoScanner.", "affectsFeature": "M2-repo-scan" }
  ]
}
```

**Required fields:** `featureId`, `salientSummary`, `whatWasImplemented`, `verification.commandsRun`, `tests.added`.
**Optional fields:** `whatWasLeftUndone`, `verification.interactiveChecks`, `discoveredIssues`.

## 2. Commit convention

- **One commit per feature.** No multi-feature commits.
- **Message format:** `<featureId>: <short description>` — e.g. `M1-git-engine: add Git.run async wrapper and error classifier`.
- **Feature ID** matches `features.json` exactly (case-sensitive).
- **Body** (optional): bulleted list of sub-changes, plus `Fulfills: VAL-X-001, VAL-Y-002` line at the end listing every assertion this commit fulfills.
- **Co-author trailer** is NOT required for these commits (personal project).
- No `--amend` across features. If a pre-commit hook fails, fix and re-commit as a NEW commit.
- No `--no-verify`.

## 3. File ownership

Kite v1 has two worker archetypes: `swiftui-worker` (UI) and `git-engine-worker` (git + parsing). The table below is the authoritative ownership map.

| Path | Owner | Notes |
|---|---|---|
| `Sources/Git/*.swift` | git-engine-worker | `Git.run`, `Git.stream`, `GitResult`, `GitError`, `ErrorClassifier` |
| `Sources/Git/Parsers/*.swift` | git-engine-worker | Porcelain parsers, log parser, status parser, diff parser, progress parser |
| `Sources/Git/Models/*.swift` | git-engine-worker | `Commit`, `Branch`, `Remote`, `RefKind`, `StatusSummary`, `LayoutRow`, etc. |
| `Sources/Git/Layout/*.swift` | git-engine-worker | Graph layout algorithm (column-reuse, first-parent preference) |
| `Sources/Repo/*.swift` | git-engine-worker | `RepoScanner`, `RepoDiscovery`, per-repo FSEvents watcher |
| `Sources/Persistence/*.swift` | swiftui-worker | `UserDefaults` + Codable settings/pins/roots |
| `Sources/App/*.swift` | swiftui-worker | `@main` App, Scene, Commands, Settings scene |
| `Sources/Views/**` | swiftui-worker | All SwiftUI views |
| `Sources/ViewModels/**` | swiftui-worker | `@Observable` models binding views to git engine |
| `Sources/Design/**` | swiftui-worker | Color palette, typography tokens, SF Symbol map |
| `Tests/GitTests/**` | git-engine-worker | Parser + engine unit tests |
| `Tests/GraphLayoutTests/**` | git-engine-worker | DAG layout tests (includes fixture repos) |
| `Tests/ViewTests/**` | swiftui-worker | Snapshot + ViewModel tests |
| `Tests/KiteUITests/**` | swiftui-worker | XCUITest end-to-end |
| `Kite.xcodeproj/` | swiftui-worker | Xcode project settings, signing, entitlements |
| `Info.plist` | swiftui-worker | Bundle ID, version, category, min system version |
| `Resources/Assets.xcassets` | swiftui-worker | App icon, color assets |
| `.factory/missions/kite-v1/**` | orchestrator only | Mission docs, validation contract, features.json |

**Conflict resolution:** If a worker needs to modify a file owned by the other archetype, it must:
1. Return to orchestrator with a `discoveredIssues` entry.
2. Not silently cross the boundary.

The orchestrator re-plans either a collaboration or a routing change.

## 4. Shared state rules

- Workers **read** `AGENTS.md` before starting any feature.
- Workers do not modify `INTERFACES.md`, `AGENTS.md`, `mission.md`, `features.json`, or `validation-contract.md`. Only the orchestrator does.
- **Per-focus observer fan-out discipline.** Each model observing `focus.lastChangeAt` spawns its own `Task` on every FS tick. Count at M6: 3 (branch list + status header + graph). M7 adds 2 (uncommitted diff + commit diff) = 5. **Consolidate into a shared `RepoDetailModel` BEFORE M7 ships** — single reload entry point, cancel-prior-task discipline built in. Not a soft recommendation: at 5 unbounded Tasks per FS tick, rapid commits produce runaway concurrency that the per-repo `GitQueue` can't fully contain.
- **`FSWatcher` is one-shot.** Call `start()` once, `stop()` once. Do not attempt to start a stopped watcher — it is a silent no-op. When switching focused repos (M3-repo-focus-lifecycle), create a **fresh** `FSWatcher` instance rather than restarting the existing one.
- Workers read `library/*.md` freely for reference.
- New reference-worthy findings go to `library/` with an orchestrator PR.
- **Environment variables required by `Process`:** `GIT_TERMINAL_PROMPT=0`, `GIT_OPTIONAL_LOCKS=0`, `LC_ALL=C`. `SSH_AUTH_SOCK` inherited from parent env. Never export credentials into the process env.
- **Working directory:** `Process.currentDirectoryURL` must be set to the repo root (from `git rev-parse --show-toplevel`), never assumed.
- **Temp files:** any scratch file must live under `FileManager.default.temporaryDirectory` and be cleaned on exit.
- **Git fixture repos for tests:** created fresh per test via `GitFixtureHelper` (in `Tests/GitTests/Support/`), torn down in test teardown. Never hardcode paths to real user repos.
- **UserDefaults keys** live under the `nl.rb2.kite.` prefix and are declared as static constants in `Sources/Persistence/Keys.swift`. No inline string literals elsewhere.

## 5. Validation gate

Before marking a feature complete, every worker must run and confirm exit code 0:

1. `xcodebuild -scheme Kite -configuration Debug build` — compiles.
2. `swift test` or `xcodebuild test -scheme Kite` — all tests green.
3. `swiftformat --lint Sources Tests` — no format violations. (Install: `brew install swiftformat`.)
4. `swiftlint --strict` — no warnings. (Install: `brew install swiftlint`.)
5. Feature-specific manual verification per the feature's `verificationSteps` in `features.json`.

For UI features, also:

6. Snapshot tests (`pointfreeco/swift-snapshot-testing`) pass with no diffs; if a diff is legitimate, update snapshot via `isRecording = true`, review visually, commit new reference.

For graph layout features:

7. Reference fixture repo layout JSON matches (`GraphLayoutTests.testFixtureRepo`).

## 6. Error escalation

Return to orchestrator (do NOT silently work around) when any of:

- A precondition (upstream feature) is not actually done, or its handoff was inaccurate.
- Requirements in `features.json` are ambiguous or contradict `validation-contract.md`.
- A cross-cutting concern affects multiple features (e.g. new `Error` case that every UI surface has to render).
- `xcodebuild` won't configure (missing Xcode, wrong Command Line Tools selected).
- A regression in an unrelated feature blocks verification.
- The feature requires touching a file outside the worker's ownership.
- SwiftLint / SwiftFormat rule conflicts with idiomatic code — surface the rule, don't silently `// swiftlint:disable`.

Format for escalation: a `discoveredIssues` entry in the handoff PLUS a separate message with `BLOCKED:` prefix and a proposed resolution.

## 7. Scrutiny review format

Every milestone ends with `scrutiny-validator-<milestone>` producing:

```json
{
  "milestoneId": "M1-foundation",
  "featureId": "scrutiny-validator-foundation",
  "status": "pass",
  "codeReview": {
    "summary": "Reviewed 5 features: git engine, parser, repo scanner, FSEvents watcher, persistence. All file ownership respected.",
    "issues": [
      {
        "file": "Sources/Git/Parsers/LogParser.swift",
        "line": 42,
        "severity": "non-blocking",
        "description": "Force-unwrap on hash parse; replace with guard + throw to match ErrorClassifier style."
      }
    ]
  },
  "sharedStateObservations": [
    { "area": "conventions", "observation": "All parsers return typed errors, no throws of raw strings. Good precedent.", "evidence": "Tests/GitTests/ErrorClassifierTests.swift" }
  ],
  "validationContractCoverage": {
    "fulfilled": ["VAL-PARSE-001", "VAL-PARSE-007", "VAL-REPO-001", "VAL-SEC-004", "VAL-SEC-005", "VAL-PERSIST-005"],
    "unverified": []
  }
}
```

Status values: `pass` | `fail` | `pass-with-non-blocking-issues`.

Scrutiny must re-run the full validation gate (§5) plus spot-check at least one assertion per feature against `validation-contract.md`.

## 8. User-testing validator format

Every milestone also ends with `user-testing-validator-<milestone>` which runs XCUITest + manual walkthroughs:

```json
{
  "milestoneId": "M5-net-ops",
  "featureId": "user-testing-validator-net-ops",
  "status": "pass",
  "walkthroughs": [
    { "script": "Fetch a repo with a new upstream commit and confirm ahead/behind updates", "result": "pass", "evidence": "screen-recording-001.mov" },
    { "script": "Push to a remote requiring SSH auth via ssh-agent", "result": "pass" },
    { "script": "Push to a remote with stale credentials", "result": "pass", "evidence": "Sticky red toast with actionable message" }
  ],
  "contractFulfillment": {
    "fulfilled": ["VAL-NET-001", "VAL-NET-002", ...],
    "partial": [],
    "failed": []
  }
}
```
