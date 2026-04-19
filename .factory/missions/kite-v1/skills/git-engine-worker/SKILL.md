---
name: git-engine-worker
description: Implements the git subprocess engine, porcelain parsers, repo scanner, FSEvents watcher, graph layout algorithm, and supporting domain models for Kite. Owns Sources/Git, Sources/Git/Parsers, Sources/Git/Layout, Sources/Git/Models, Sources/Repo, and Tests/GitTests + Tests/GraphLayoutTests. Does NOT touch SwiftUI views, ViewModels, toasts, menu commands, Xcode project settings, Info.plist, or Assets. Exposes typed results; views consume them.
---

# git-engine-worker

## When to use

Route to this worker when a feature involves:

- Shelling out to `/usr/bin/git` via `Process`
- Parsing git porcelain output
- Classifying git error stderr into typed errors
- Enumerating repos under root paths
- Watching `.git/` directories via FSEvents
- Computing the commit DAG layout (column-reuse algorithm)
- Domain model types (`Commit`, `Branch`, `Remote`, `StatusSummary`, `LayoutRow`)

Features likely to use this worker: M1-git-engine, M1-git-parsers, M1-fs-watcher, M2-repo-scan, M3-repo-focus-lifecycle, M4-graph-layout.

## Required sub-skills

- Swift Testing for unit tests.
- `GitFixtureHelper` under `Tests/GitTests/Support/` (create if not exists) for spinning up real fixture repos in `FileManager.default.temporaryDirectory`.

## Work procedure

1. **Read context**:
   - `mission.md`, `AGENTS.md`, `INTERFACES.md`
   - `library/git-cli-integration.md` — exhaustive reference for git CLI flags, porcelain output shapes, error classes.
   - `library/git-graph-rendering.md` §1 (the layout algorithm) — only for the layout feature.
   - `validation-contract.md` — the VAL-IDs the feature fulfills (especially VAL-PARSE-*, VAL-SEC-*, VAL-GRAPH-002/003/006).
   - The feature's entry in `features.json`.

2. **Verify preconditions** (per INTERFACES.md §6).

3. **Design pure functions first**. The engine is best tested when parsers and layout are pure `(Input) -> Output` functions. Only `Git.run` and `FSWatcher` have side effects.

   **Pattern (established in M1-git-parsers):**
   - **Stateless parsers** (input fully parsed per call) → `enum` namespace with `static func parse(...) throws -> Result`. Examples: `BranchParser`, `LogParser`, `StatusParser`, `ForEachRefParser`, `DiffParser`.
   - **Stateful stream consumers** (carry state across chunks, dedup, or buffer partials) → `final class` with a `func consume(_:) -> Event?` method. Example: `ProgressParser` — carry-buffer + last-emitted dedup across `\r`-chunked input.
   - **Algorithms over immutable data** (graph layout) → `enum` namespace with `static func compute(...) -> [Row]`.
   Pick the right shape upfront; don't mix.

4. **Write tests first (RED)**: fixture-based tests in `Tests/GitTests/`. For each parser, add:
   - Happy-path test with real git output captured from a fixture repo.
   - Empty-output test.
   - At least one pathological edge case (binary file, empty commit, newline-in-subject, unicode branch name, detached HEAD, shallow clone).

5. **Implement (GREEN)**. Hardcode `/usr/bin/git` path. Always pass `GIT_TERMINAL_PROMPT=0`, `GIT_OPTIONAL_LOCKS=0`, `LC_ALL=C` in the process environment. Use null-delimited output (`-z`, `%x00`) wherever git supports it. Never use a shell (`Process` uses argv, not `sh -c`).

6. **For the layout algorithm specifically**:
   - Implement the column-reuse algorithm with first-parent preference exactly as described in `library/git-graph-rendering.md` §1.
   - Create a committed fixture repo under `Tests/GraphLayoutTests/Fixtures/` (script that sets up the repo deterministically).
   - Snapshot the expected `[LayoutRow]` as JSON in `Tests/GraphLayoutTests/Reference/fixtureRepo.json`.
   - Any future layout change that alters the reference requires explicit reference-JSON update + scrutiny review.

7. **Do not modify files owned by `swiftui-worker`** (see INTERFACES.md §3). If a new view needs a specific model shape, return a `discoveredIssues` suggesting an addition.

8. **Run the validation gate** (INTERFACES.md §5).

9. **Manual verification** per `verificationSteps`. For engine features, that means unit tests green + a sanity run of `Git.run([\"--version\"], cwd: tmpRepo)` or similar, not UI walkthroughs.

10. **Commit once** with `<featureId>: <short description>` and a body listing fulfilled VAL-IDs.

11. **Produce handoff JSON** and return to orchestrator.

## Example handoff

```json
{
  "featureId": "M4-graph-layout",
  "salientSummary": "Column-reuse layout with first-parent preference implemented and tested against a 47-commit fixture repo matching the committed reference JSON. 14 unit tests green. VAL-GRAPH-002, VAL-GRAPH-003, VAL-GRAPH-006 fulfilled.",
  "whatWasImplemented": "Added Sources/Git/Layout/GraphLayout.swift (pure function computeLayout([Commit]) -> [LayoutRow]), Sources/Git/Models/LayoutRow.swift (struct with column, inEdges, outEdges, refs), Sources/Git/Layout/LanePalette.swift (name-hash → 6-color mapping with main/master/trunk/default hardcoded to slot 0). Fixture repo setup script at Tests/GraphLayoutTests/Fixtures/setup_fixture.sh builds the canonical 47-commit DAG deterministically. Reference JSON at Tests/GraphLayoutTests/Reference/fixtureRepo.json.",
  "whatWasLeftUndone": "",
  "verification": {
    "commandsRun": [
      { "command": "swift test --filter GraphLayoutTests", "exitCode": 0, "observation": "14 of 14 passed in 0.31s" },
      { "command": "bash Tests/GraphLayoutTests/Fixtures/setup_fixture.sh /tmp/kite-layout-fixture && swift test --filter GraphLayoutTests.testFixtureRepo", "exitCode": 0, "observation": "Reference matches computed layout" }
    ],
    "interactiveChecks": []
  },
  "tests": {
    "added": [
      {
        "file": "Tests/GraphLayoutTests/GraphLayoutTests.swift",
        "cases": [
          { "name": "testFirstParentStaysInLane", "verifies": "VAL-GRAPH-003" },
          { "name": "testColumnReusedAfterMerge", "verifies": "VAL-GRAPH-002" },
          { "name": "testOctopusMergeUsesStraightLines", "verifies": "VAL-GRAPH-006" },
          { "name": "testFixtureRepo", "verifies": "VAL-GRAPH-002" }
        ]
      }
    ]
  },
  "discoveredIssues": []
}
```

## When to return to orchestrator

- A library documented a flag that doesn't exist on the user's git version (`/usr/bin/git --version` < 2.40).
- A parser can't robustly handle a real-world output you observed — surface the case and ask whether to defer.
- The layout reference JSON needs to change because of a correctness fix — flag it for scrutiny review before committing.
- `Process` exhibits a platform-specific issue that would require AppKit-level workaround.
- You find a VAL-SEC-* grep invariant that would be violated by your change.

## Never mark complete if

- A parser test is skipped or expected-to-fail.
- The layout reference JSON was updated without explicit scrutiny.
- `Process` is invoked with any of: `--force`, `--force-with-lease`, `reset --hard`, `clean -f`, `stash`, `commit`, `merge`, `rebase`, `cherry-pick`, `push -f`.
- You didn't set `GIT_TERMINAL_PROMPT=0` and `GIT_OPTIONAL_LOCKS=0` on every `Process`.
- You relied on `PATH` lookup for `git` instead of absolute `/usr/bin/git`.
- You mocked `git` output in tests instead of using real fixture repos. (One narrow exception: `ProgressParser` tests may use literal `\r`-containing strings as that's a pure parser, not an execution.)
- A layout change broke the committed reference JSON without explicit reference update + scrutiny.
