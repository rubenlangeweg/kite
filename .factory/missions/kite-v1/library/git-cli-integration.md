# Git CLI Integration Guide (Shell-Out Pattern)

Research artifact for gitruben v1. All git operations go through `/usr/bin/git`
invoked as a subprocess from Swift. No libgit2. Covers commands, output
formats, parsing, error handling, and Swift integration.

macOS ships `git` at `/usr/bin/git` (Xcode CLT, currently 2.50.1). Pin to this
path rather than relying on `$PATH`.

---

## 1. Detecting a repo and scanning `/Users/ruben/Developer`

### Is a directory a git repo?

```
git -C <dir> rev-parse --is-inside-work-tree --show-toplevel
```

Output on success: `true\n<absolute-path>\n`. On failure, exit 128 with stderr
`fatal: not a git repository ...`. Use exit code, not stdout, as the signal.
`--show-toplevel` gives the canonical root so we key repos by stable path.

For a bare repo `--is-inside-work-tree` prints `false`; `--is-bare-repository`
prints `true`. v1 skips bare repos (see Edge cases).

### Efficient scan

Do NOT shell out to git per directory. Walk the filesystem in Swift and look
for `.git` entries directly — a dir is a repo iff it contains a `.git` that's
a directory (normal) or a file (gitfile: worktrees/submodules).

1. BFS from `/Users/ruben/Developer` with `FileManager.enumerator`.
2. At each dir, `stat` for `.git`. If present: record the dir and stop
   descending — we don't want to surface nested submodule checkouts.
3. Prune these names unconditionally: `node_modules`, `.build`, `DerivedData`,
   `.swiftpm`, `Pods`, `vendor`, `.venv`, `venv`, `__pycache__`, `.next`,
   `.nuxt`, `dist`, `build`, `target`, `.gradle`, `.idea`, `.vscode`,
   `.cache`.
4. Skip anything starting with `.` except the `.git` probe itself.

A typical Developer/ tree of ~5k directories scans in <200ms on SSD.
Cache the result to `~/Library/Application Support/gitruben/repo-cache.json`
and watch the parent with `FSEventStream` for `IN_CREATE`/`IN_DELETE` to keep
it fresh.

---

## 2. Listing branches

```
git branch --list --format='%(refname:short)%00%(objectname)%00%(upstream:short)%00%(upstream:track)'
```

Each newline-terminated record has four NUL-separated fields. NUL eliminates
ambiguity if a branch name contains the field separator. Sample:

```
master\x007fd1a60b01f91b314f59955a4e4d4e80d8edf11d\x00origin/master\x00
feature/x\x00abc123...\x00origin/feature/x\x00[ahead 2]
stale\x00def456...\x00origin/stale\x00[ahead 1, behind 4]
orphan\x00123abc...\x00\x00
```

Fields: `name`, `oid` (40 hex), `upstream` short ref or empty, `track` bracket
string. Track values: empty (in sync / no upstream), `[gone]` (upstream was
deleted), `[ahead N]`, `[behind N]`, `[ahead N, behind M]`. Extract ahead/
behind with regex `ahead (\d+)` / `behind (\d+)`.

Remote-tracking branches use same format scoped differently:

```
git for-each-ref --format='%(refname:short)%00%(objectname)' refs/remotes/
```

Skip entries ending in `/HEAD` — symbolic ref to the default branch; we don't
want a duplicate lane.

### Current branch

`git symbolic-ref --short HEAD` — prints branch, or exits 1 with `fatal: ref
HEAD is not a symbolic ref` when detached. Handle detached explicitly (§13).

---

## 3. Listing remotes

```
git remote -v
```

```
origin	https://github.com/octocat/Hello-World.git (fetch)
origin	https://github.com/octocat/Hello-World.git (push)
upstream	git@github.com:foo/bar.git (fetch)
upstream	git@github.com:foo/bar.git (push)
```

Tab-separated. Each remote appears twice (fetch + push). Deduplicate by name;
only keep both URLs when they differ. One `remote -v` parse is cheaper than
`remote` + N `get-url` calls.

---

## 4. Commit graph data

```
git log --all --topo-order --format='%H%x00%P%x00%an%x00%ae%x00%at%x00%s' -n 200
```

Fields (NUL-separated, `\n` ends record): `%H` full SHA; `%P` space-separated
parents (empty for root); `%an`/`%ae` author name/email; `%at` author date
(Unix seconds); `%s` subject. Real sample from octocat/Hello-World:

```
b1b3f972...\x007fd1a60b...\x00The Octocat\x00support+octocat@github.com\x001525974919\x00sentence case
7fd1a60b...\x00553c2077... 762941318...\x00The Octocat\x00octocat@nowhere.com\x001331075210\x00Merge pull request #6
553c2077...\x00\x00cameronmcefee\x00cameron@github.com\x001296068768\x00first commit
```

Merges have 2+ parents; root has empty parents (`\x00\x00`). `-n 200` caps
initial load; paginate with `--skip=N -n 200` as the user scrolls.
`--topo-order` (parents after children) is right for graph rendering;
`--date-order` gives nicer "recent activity" lists but worse DAGs.

### Reconstructing DAG lanes (X columns)

Do NOT use `git log --graph` — it emits ASCII art you'd have to reverse-
engineer. Compute lanes ourselves. Simplest correct algorithm, O(n) sweep
in topo order:

```
activeLanes: [CommitSHA?]   // index = X column; value = next SHA expected

for each commit c in topo order (newest-first):
    // Find a lane expecting c, else claim the leftmost empty lane
    // (append new lane if none free).
    col = activeLanes.firstIndex { $0 == c.sha }
       ?? activeLanes.firstIndex { $0 == nil }
       ?? activeLanes.append(nil)
    c.column = col
    activeLanes[col] = nil                      // free; reassign below

    for (i, p) in c.parents.enumerated():
        if i == 0:
            activeLanes[col] = p                // first parent keeps lane
        else:
            let new = activeLanes.firstIndex { $0 == nil }
                   ?? activeLanes.append(nil)
            activeLanes[new] = p                // merge-from lane
```

Edges are `(childSha, parentSha, childCol, parentCol)` tuples, painted as
curves between rows. Refinements to add later: lane reuse compaction (already
in the snippet), stable per-branch colors (join with `for-each-ref`),
straight-line first-parent placement. This is standard "swimlane" layout —
same approach as GitKraken/Fork/GitUp.

---

## 5. Refs on commits

`git log --decorate=full` embeds refs inline with the subject, which makes
parsing awkward. Prefer a separate `for-each-ref` pass then join by SHA:

```
git for-each-ref --format='%(objectname) %(refname)'
```

Real sample:

```
7fd1a60b01f91b314f59955a4e4d4e80d8edf11d refs/heads/master
7fd1a60b01f91b314f59955a4e4d4e80d8edf11d refs/remotes/origin/HEAD
7fd1a60b01f91b314f59955a4e4d4e80d8edf11d refs/remotes/origin/master
b1b3f9723831141a31a1a7252a213e216ea76e56 refs/remotes/origin/octocat-patch-1
b3cbd5bbd7e81436d2eee04537ea2b4c0cad4cdf refs/remotes/origin/test
```

Build a `[SHA: [Ref]]` dictionary and render chips on each commit node.
Classify by prefix: `refs/heads/` = local, `refs/remotes/<remote>/` = remote-
tracking (skip `.../HEAD`), `refs/tags/` = tag. For annotated tags, use
`--format='%(objectname) %(*objectname) %(refname)'` so you get the target
commit in `*objectname`.

Attach a `HEAD` pseudo-ref via `git symbolic-ref --short HEAD` (branch) or
`git rev-parse HEAD` (detached).

---

## 6. Status

```
git status --porcelain=v2 --branch -z
```

v2 porcelain is the stable, script-friendly format. `--branch` prepends branch
metadata; `-z` makes records NUL-terminated so paths-with-specials don't need
C-quoting. Real sample (shown with `\n` separators for readability):

```
# branch.oid 7fd1a60b01f91b314f59955a4e4d4e80d8edf11d
# branch.head master
# branch.upstream origin/master
# branch.ab +0 -0
1 .M N... 100644 100644 100644 980a0d5f... 980a0d5f... README
1 A. N... 000000 100644 100644 000000... ce013625... newfile.txt
```

Line types:

- `# branch.oid <sha>` — HEAD SHA.
- `# branch.head <name>` — branch, or `(detached)`.
- `# branch.upstream <ref>` — only if upstream set.
- `# branch.ab +N -M` — ahead/behind vs upstream (only if upstream set).
- `1 XY ...` — ordinary changed entry. `XY` is two letters: index side then
  worktree side. `.` unmodified, `M` modified, `A` added, `D` deleted,
  `R` renamed, `C` copied, `U` unmerged, `T` type changed. E.g. `A.` = staged
  add, `.M` = unstaged modification, `MM` = staged modification + further
  worktree modification.
- `2 XY ...` — renamed/copied entry (score + both paths).
- `u XY ...` — unmerged (conflicts).
- `? path` — untracked.
- `! path` — ignored (only with `--ignored`, which we don't pass).

With `-z`, renames appear as `<entry>\0<newpath>\0<oldpath>\0`.

---

## 7. Diff

```
git diff --no-color --patch -U3           # unstaged: worktree vs index
git diff --no-color --patch -U3 --staged  # staged: index vs HEAD
git show --no-color --patch <sha>         # commit vs its first parent
```

`--no-color` avoids ANSI escapes if the user has `color.ui = always`.
`--patch` is the default for `diff` but explicit is safer. `-U3` is the
default context; bump it for "show more context" actions.

### Unified diff format

Real sample from an edited file:

```
diff --git a/README b/README
index 980a0d5..e4f73f1 100644
--- a/README
+++ b/README
@@ -1 +1,2 @@
 Hello World!
+modified
```

Parse in four passes per file:

1. **File header**: `diff --git a/<path> b/<path>`. Start a new FileDiff.
   Paths after `a/` and `b/` may differ (rename). Watch for: `new file mode
   <mode>`, `deleted file mode <mode>`, `rename from <old>` + `rename to
   <new>`, `similarity index N%`, `Binary files ... differ` (no hunks).
2. **Index line**: `index <oldsha>..<newsha> <mode>`. Useful for "view file
   at old version" via `git show <oldsha>:<path>`.
3. **`---` / `+++`**: old/new path markers. `/dev/null` means added/deleted.
4. **Hunks**: `@@ -<oldStart>,<oldLen> +<newStart>,<newLen> @@ [func context]`.
   Body lines: `' '` context, `'+'` added, `'-'` removed, `'\'` "No newline
   at end of file" (attach to previous line).

Represent each hunk as `{ oldStart, oldLen, newStart, newLen, lines }`; track
`(oldLineNo, newLineNo)` per line for gutter rendering. For large diffs
(>~1MB or >~1000 files), stream line-by-line and call `git diff --stat` first
to decide whether to offer "summary only."

---

## 8. Network operations

Never run these on the main thread — seconds to minutes. All three inherit
credentials from env + git config.

```
git fetch --all --prune --progress
git pull --ff-only --progress
git push --progress
```

- `--all` (fetch) — every remote.
- `--prune` (fetch) — drop local remote-tracking branches whose upstream was
  deleted.
- `--progress` — force progress to stderr even though we're not a TTY.
- `--ff-only` (pull) — refuse anything that isn't a fast-forward. If the
  remote diverged, stderr contains `fatal: Not possible to fast-forward,
  aborting.` Surface as "Pull would create a merge — rebase/merge manually."
  For v1, never rebase-pull or merge-pull automatically.
- `push` with no args pushes current branch to its upstream. If none, stderr
  has `fatal: The current branch foo has no upstream branch.` plus a hint
  `To push ... use git push --set-upstream origin foo`. Surface as
  "Publish branch to origin" — run
  `git push --set-upstream origin <branch> --progress`.

### Progress parsing

Git writes progress to stderr using `\r` to overwrite the same line. Sample
fetch stderr (each record ends in `\r`, terminal with `\n`):

```
remote: Enumerating objects: 42, done.\r
remote: Counting objects:  50% (21/42)\r
remote: Counting objects: 100% (42/42), done.\r
remote: Compressing objects:  33% (1/3)\r
remote: Compressing objects: 100% (3/3), done.\r
Unpacking objects:  25% (1/4)\r
Unpacking objects: 100% (4/4), done.\n
```

Split on BOTH `\r` and `\n`. Extract percentages with:

```
^(?:remote: )?(?<phase>[A-Za-z ]+?):\s+(?<pct>\d+)% \((?<cur>\d+)/(?<total>\d+)\)
```

Emit `Progress(phase, percent, cur, total)` at ~10 Hz, coalescing — don't
update UI per line. Lines without percentages are status messages, log them
verbatim.

### Error classes

Scan the final stderr after non-zero exit and classify:

- **Auth required** — `fatal: Authentication failed for 'https://...'`,
  `fatal: could not read Username for 'https://...': terminal prompts
  disabled`, `Permission denied (publickey).`
- **Non-fast-forward push** — `! [rejected] <b> -> <b> (non-fast-forward)`
  / `Updates were rejected because the tip of your current branch is behind`.
  Suggest pull-then-push, or force-with-lease with confirmation.
- **No upstream on push** — `fatal: The current branch X has no upstream
  branch.` → "Publish."
- **No upstream on pull** — `There is no tracking information for the current
  branch.` → offer "Set upstream to origin/X" if that ref exists.
- **Network/DNS** — `fatal: unable to access ...: Could not resolve host:`,
  `ssh: Could not resolve hostname ...`.
- **Dirty tree blocking pull** — `error: Your local changes to the following
  files would be overwritten by merge:` → suggest stash or commit.

Wrap each class in a `GitError` case so the UI shows a dedicated banner + CTA,
never raw stderr.

---

## 9. Authentication on macOS

v1 never prompts for creds in-app. We rely entirely on what the user has
configured for their terminal git.

### SSH

Our Process inherits `SSH_AUTH_SOCK`, so git-over-SSH talks to the user's
running ssh-agent (launchd-provided). Keys added via `ssh-add` Just Work.
For encrypted keys without agent, OpenSSH falls back to `SSH_ASKPASS`, which
macOS routes through Keychain when `~/.ssh/config` has:

```
Host *
    UseKeychain yes
    AddKeysToAgent yes
    IdentityFile ~/.ssh/id_ed25519
```

Onboarding check: run `ssh -T git@github.com -o BatchMode=yes -o
StrictHostKeyChecking=accept-new` once and report.

### HTTPS

macOS ships `git-credential-osxkeychain`. Verify with `git config --global
credential.helper`; expect `osxkeychain`. If missing, offer to set it:

```
git config --global credential.helper osxkeychain
```

Git calls the helper, which looks up `host:user` in the login keychain. If
nothing is stored, the helper returns empty, git tries to prompt, and
`GIT_TERMINAL_PROMPT=0` makes it fail cleanly instead of hanging.

### Environment variables on every invocation

```swift
var env = ProcessInfo.processInfo.environment
env["GIT_TERMINAL_PROMPT"] = "0"     // never hang on missing creds
env["GIT_ASKPASS"] = ""              // prevent legacy askpass hang
env["SSH_ASKPASS"] = ""              // same for ssh
env["LC_ALL"] = "C"                  // stable, parseable English output
env["LANG"] = "C"
env["GIT_OPTIONAL_LOCKS"] = "0"      // don't take index lock for reads
env["GIT_PAGER"] = "cat"             // belt + braces; --no-pager on cmd
```

`GIT_OPTIONAL_LOCKS=0` stops read-only commands (status, log, branch) from
contending with the user's terminal git for `index.lock` — critical when the
app polls status while a terminal commit is in flight.

Inherit the full user env (preserves `SSH_AUTH_SOCK` and any custom credential
helpers), then overlay the keys above. Never whitelist-filter to a minimal
set.

---

## 10. Branch operations

**Always prefer `git switch` over `git checkout`.** `switch` (git 2.23+) has
narrower semantics and fails loudly instead of silently doing something
surprising (`checkout <path>` discards changes; `switch <path>` errors).

```
git switch <name>                  # switch to existing
git switch -c <name> [<start>]     # create and switch
git branch <name> [<start>]        # create without switching
git branch -d <name>               # safe delete (refuses if unmerged)
git branch -D <name>               # force delete
git branch -m <old> <new>          # rename (omit <old> to rename current)
git push origin --delete <name>    # delete remote
```

v1: use `-d` first. If it fails with `error: the branch '<name>' is not fully
merged`, confirm dialog then `-D`.

Errors to handle on switch:

- **Dirty tree blocks switch**:
  ```
  error: Your local changes to the following files would be overwritten by checkout:
      <path>
  Please commit your changes or stash them before you switch branches.
  Aborting
  ```
  Surface as "Uncommitted changes — stash or commit first." Offer a Stash
  button: `git stash push -m "gitruben autostash <timestamp>"`, retry the
  switch, then pop.
- **No such branch** — `fatal: invalid reference: <name>`.
- **Already exists on create** — `fatal: A branch named '<name>' already
  exists.`

---

## 11. Streaming vs capturing

Two modes:

**Capture** — short, bounded reads (< 1s typical). Collect stdout/stderr into
buffers, return on exit. Use for: `rev-parse`, `branch --list`,
`for-each-ref`, `status`, `log -n 200`, `remote -v`, `config --get`, small
`diff`, `show`.

```swift
struct GitResult { let exitCode: Int32; let stdout: Data; let stderr: Data }
```

**Stream** — long ops + large diffs. Async line readers on stdout AND stderr,
emit events as they arrive. Use for: `fetch`, `pull`, `push`, `clone`, diffs
larger than a few MB, log pagination over huge histories.

```swift
enum GitEvent {
    case stdoutLine(String)
    case stderrLine(String)
    case progress(phase: String, percent: Int, cur: Int, total: Int)
    case finished(exitCode: Int32)
}
```

Split stderr on both `\r` and `\n`; split stdout on `\n`. Read both pipes
concurrently on background queues — git writes stderr faster than a single-
threaded reader can drain during `Counting objects`, causing pipe-buffer
deadlock. Always await termination after draining both streams or the process
becomes a zombie holding an fd.

---

## 12. Performance tips

- **`--no-pager`** on every command (or `GIT_PAGER=cat`). Avoids blocking on
  pager checks and stray `\x1b[?1049h` terminal sequences.
- **Avoid `git log --graph`** — its ASCII art is unreliable to parse; we
  compute lanes ourselves (§4).
- **`-z` / NUL-delimited** on `status`, `ls-files`, `diff --name-only`,
  `check-attr` — eliminates path-quoting ambiguity.
- **`--format` explicit** — defends against user config like
  `log.decorate = full` or custom `pretty.*` aliases.
- **`--no-color`** — prevents ANSI leaking in when `color.ui = always`.
- **`-C <dir>`** — don't `chdir`; equivalent and enables concurrent commands
  against different repos.
- **Concurrency** — git is multi-process-safe for reads; up to ~4 concurrent
  read-only commands per repo is fine. Serialize writes (fetch/push/commit)
  per repo with a Swift lock.
- **Don't reuse processes** — git is one-shot; macOS `fork+exec` is ~1–2ms,
  not a hotspot.
- **Commit graph cache** — `git commit-graph write --reachable
  --changed-paths` dramatically speeds up `log --all` on large repos. Offer
  as a background "optimize" action; don't run automatically (writes to
  `.git/`).

---

## 13. Edge cases

**Detached HEAD** — `git symbolic-ref --short HEAD` exits 1 with `fatal: ref
HEAD is not a symbolic ref`. Fall back to `git rev-parse HEAD` for the SHA.
Label "Detached at `<sha7>`". When the user checks out a specific commit,
warn: "Changes won't be on any branch. Create a branch to keep this state."

**Bare repos** — `git rev-parse --is-bare-repository` = `true`. No worktree,
no status. v1: detect during scan and skip.

**Worktrees** — `git worktree list`:

```
/Users/ruben/Developer/foo         abc1234 [main]
/Users/ruben/Developer/foo-feat    def5678 [feature/x]
```

Each worktree has its own HEAD/index/worktree but shares objects. We'll
encounter them during scan — they contain a `.git` file (not dir). Detect via
`git rev-parse --git-common-dir` ≠ `--git-dir`. v1: surface each as its own
row under the main repo.

**Submodules** — v1: ignore. Prune their `.git` during scan. They appear in
status as `160000` entries — filter out of the UI.

**Symbolic refs** — `HEAD` → branch name, `refs/remotes/origin/HEAD` → remote
default branch. Read with `git symbolic-ref <ref>` or
`git for-each-ref --format='%(symref)' <ref>`. Only `HEAD` and `origin/HEAD`
matter in v1; skip `origin/HEAD` in branch lists (§5).

**Empty repo** — `git log` fails with `fatal: your current branch 'master'
does not have any commits yet`. Detect via `git rev-parse --verify HEAD`
exit 1. Show empty state, offer "Make first commit."

**LFS** — `git lfs` is a separate binary. v1: treat pointers as normal text;
diffs show readable pointer content. Detect via `.gitattributes` containing
`filter=lfs` and show a notice.

---

## 14. Swift integration: `GitCommand`

### Signatures

```swift
struct GitResult {
    let exitCode: Int32
    let stdout: Data
    let stderr: Data
    var stdoutString: String { String(data: stdout, encoding: .utf8) ?? "" }
    var stderrString: String { String(data: stderr, encoding: .utf8) ?? "" }
    var isSuccess: Bool { exitCode == 0 }
}

enum GitError: Error {
    case nonZeroExit(code: Int32, stderr: String)
    case notARepo(URL)
    case authRequired
    case nonFastForward
    case noUpstream(branch: String)
    case dirtyTreeBlocksSwitch(paths: [String])
    case launchFailed(Error)
}

enum GitCommand {
    static func run(args: [String], cwd: URL, timeout: TimeInterval = 30)
        async throws -> GitResult                      // capture mode
    static func stream(args: [String], cwd: URL,
                       onEvent: @escaping (GitEvent) -> Void)
        async throws -> Int32                          // stream mode
}
```

### Implementation sketch (capture mode)

```swift
extension GitCommand {
    static func run(args: [String], cwd: URL, timeout: TimeInterval = 30)
        async throws -> GitResult
    {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = cwd
        process.arguments = ["--no-pager"] + args

        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_ASKPASS"] = ""; env["SSH_ASKPASS"] = ""
        env["LC_ALL"] = "C"; env["LANG"] = "C"
        env["GIT_OPTIONAL_LOCKS"] = "0"; env["GIT_PAGER"] = "cat"
        process.environment = env

        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do { try process.run() }
                catch { cont.resume(throwing: GitError.launchFailed(error)); return }

                // Drain both pipes concurrently to avoid deadlock.
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                cont.resume(returning: GitResult(
                    exitCode: process.terminationStatus,
                    stdout: outData, stderr: errData))
            }
        }
    }
}
```

Production note: replace the blocking `readDataToEndOfFile` with async
`DispatchSource` line readers — the snippet above deadlocks on outputs larger
than one pipe buffer (~64KB). Fine for small captures, not for diffs.

### Worked example — list branches

```swift
struct BranchInfo {
    let name: String
    let oid: String
    let upstream: String?
    let ahead: Int
    let behind: Int
    let isGone: Bool
}

extension GitCommand {
    static func listBranches(repo: URL) async throws -> [BranchInfo] {
        let fmt = "%(refname:short)%00%(objectname)%00%(upstream:short)%00%(upstream:track)"
        let result = try await run(
            args: ["branch", "--list", "--format=\(fmt)"], cwd: repo)
        guard result.isSuccess else {
            throw GitError.nonZeroExit(
                code: result.exitCode, stderr: result.stderrString)
        }

        return result.stdoutString
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> BranchInfo? in
                let f = line.split(separator: "\0", omittingEmptySubsequences: false)
                guard f.count >= 4 else { return nil }
                let track = String(f[3])
                return BranchInfo(
                    name: String(f[0]),
                    oid: String(f[1]),
                    upstream: f[2].isEmpty ? nil : String(f[2]),
                    ahead: parseInt(in: track, after: "ahead ") ?? 0,
                    behind: parseInt(in: track, after: "behind ") ?? 0,
                    isGone: track.contains("gone"))
            }
    }

    private static func parseInt(in s: String, after prefix: String) -> Int? {
        guard let r = s.range(of: prefix) else { return nil }
        return Int(s[r.upperBound...].prefix(while: { $0.isNumber }))
    }
}
```

Usage:

```swift
let branches = try await GitCommand.listBranches(
    repo: URL(fileURLWithPath: "/Users/ruben/Developer/gitruben"))
for b in branches {
    print("\(b.name) @ \(b.oid.prefix(7)) ↑\(b.ahead) ↓\(b.behind)")
}
```

---

## Quick reference: every command the app runs

| Operation         | Command                                                             | Mode     |
|-------------------|---------------------------------------------------------------------|----------|
| Is repo           | `git -C D rev-parse --is-inside-work-tree --show-toplevel`          | capture  |
| Current branch    | `git symbolic-ref --short HEAD`                                     | capture  |
| Branches          | `git branch --list --format=...`                                    | capture  |
| Remote branches   | `git for-each-ref --format=... refs/remotes/`                       | capture  |
| Tags              | `git for-each-ref --format=... refs/tags/`                          | capture  |
| Remotes           | `git remote -v`                                                     | capture  |
| Log (graph data)  | `git log --all --topo-order --format=... -n 200`                    | capture  |
| Status            | `git status --porcelain=v2 --branch -z`                             | capture  |
| Diff unstaged     | `git diff --no-color --patch -U3`                                   | capture  |
| Diff staged       | `git diff --no-color --patch -U3 --staged`                          | capture  |
| Show commit       | `git show --no-color --patch <sha>`                                 | capture  |
| Fetch             | `git fetch --all --prune --progress`                                | stream   |
| Pull              | `git pull --ff-only --progress`                                     | stream   |
| Push              | `git push --progress`                                               | stream   |
| Publish branch    | `git push --set-upstream origin <name> --progress`                  | stream   |
| Create branch     | `git switch -c <name> [<start>]`                                    | capture  |
| Switch branch     | `git switch <name>`                                                 | capture  |
| Delete branch     | `git branch -d <name>` (escalate to `-D` on confirm)                | capture  |
| Worktrees         | `git worktree list`                                                 | capture  |

Every invocation prefixes `--no-pager` and uses the env block from §9.

---

## Known parser limitations (post-M1-git-parsers findings)

1. **`DiffParser` does not handle quoted-path diff headers.** Git emits `diff --git "a/foo bar" "b/foo bar"` (with quotes and embedded space) when filenames contain spaces or non-printable characters. The current `extractDiffGitPaths` implementation returns `nil` and the resulting `FileDiff` leaves `oldPath`/`newPath` unset. M7-uncommitted-diff and M7-commit-diff MUST extend `extractDiffGitPaths` before shipping against repos with space-in-filename diffs. Emit a `Logger` warning at the extract site so silent drops are observable during dev.

2. **`ProgressParser.consume(_:)` returns only the LAST `ProgressEvent` per chunk.** Intermediate percent updates within a chunk are lost. If M5-fetch needs smooth frame-by-frame progress, add `consumeAll(_:) -> [ProgressEvent]` or switch the parser to an `AsyncStream<ProgressEvent>` shape. For v1 toolbar indicator, last-per-chunk is acceptable.

3. **`Git.run` captures output only post-termination via `readToEnd()`.** Safe for commands whose combined stdout+stderr stays under ~64 KB (pipe-buffer size). Large-output commands (`git diff`, `git show`, `git log --patch`, `git archive`) **will pipe-buffer-deadlock the child**. Use `Git.stream` for those OR refactor `Git.run` to drain both pipes concurrently via `readabilityHandler`. Tracked as fix feature `M1-fix-git-run-drain`, scheduled pre-M7.

