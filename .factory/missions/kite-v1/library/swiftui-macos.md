# SwiftUI on macOS — A Practical Guide for Building gitruben

Target: macOS 15 Sequoia / macOS 26 Tahoe, Xcode 16+, Swift 5.9+ (Observation macro),
personal use (no Apple Developer account). The author is a strong full-stack
engineer but new to SwiftUI. This guide is opinionated; where there is more than
one way to do something, the recommended path is marked **[do this]**.

---

## 1. Project scaffolding

### 1.1 Create the project

In Xcode 16/26:

1. **File → New → Project → macOS → App**.
2. Product Name: `gitruben`. Team: *None*. Interface: **SwiftUI**. Language:
   **Swift**. Testing System: **Swift Testing** (Xcode 16 default) *and* add an
   XCTest target later for snapshot-style tests — the two coexist.
3. Storage: **None** (we will pick persistence manually; do not let Xcode wire
   SwiftData in for you).
4. Include Tests: **yes**.
5. Uncheck "Use Core Data".

Xcode 16 no longer generates an `AppDelegate.swift`; the `@main` struct is the
entry point. Skip `NSApplicationDelegateAdaptor` until you have a real need
(menu-bar extras, dock click behavior, URL schemes).

### 1.2 App / Scene structure

```swift
import SwiftUI

@main
struct GitrubenApp: App {
    // Single source of truth for the whole app. @State owns the instance.
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup("gitruben") {
            RootView()
                .environment(appModel)            // inject into the tree
                .frame(minWidth: 1100, minHeight: 700)
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            GitrubenCommands(model: appModel)     // menu bar items (see §2.3)
        }

        // Preferences window — macOS-only, free from SwiftUI.
        Settings {
            SettingsView()
                .environment(appModel)
        }
    }
}
```

- `WindowGroup` gives multi-window support automatically. For single-window,
  use `Window("gitruben", id: "main")`.
- `Settings { }` creates the standard ⌘, Preferences window.
- `.windowToolbarStyle(.unified)` matches native apps; `.unifiedCompact` is
  denser.
- On macOS 15+, `.containerBackground(.ultraThinMaterial, for: .window)` blends
  the titlebar.

### 1.3 Info.plist essentials

Xcode 16 edits Info.plist via the target's **Info** tab. Set:

- `LSMinimumSystemVersion` = 15.0 (or 14.0 for Sonoma support).
- `CFBundleDisplayName` = `gitruben`.
- `LSApplicationCategoryType` = `public.app-category.developer-tools`.
- `NSDocumentsFolderUsageDescription`, `NSDesktopFolderUsageDescription`,
  `NSDownloadsFolderUsageDescription` — only if sandbox stays on (see §11).

You do **not** need `NSAppTransportSecurity` (no HTTP networking) or
`UIApplicationSceneManifest` (iOS only).

### 1.4 Sandboxing — turn it off

For personal use, the App Sandbox is more trouble than it is worth. A git
client reads `.git` directories anywhere on disk, executes `/usr/bin/git`,
and writes to arbitrary working trees. The sandbox blocks `Process` launching
external binaries unless you add painful exceptions, and requires
security-scoped bookmarks per repo.

**[do this]** In **Signing & Capabilities**, remove **App Sandbox** entirely.
Leave **Hardened Runtime** off (see §12). Set signing to **Sign to Run
Locally**. If you later ship, re-add sandbox +
`com.apple.security.files.user-selected.read-write` +
`...bookmarks.app-scope` + an XPC helper for git.

---

## 2. App layout patterns

### 2.1 Three-pane NavigationSplitView

The canonical macOS three-pane layout. On macOS 15+, `NavigationSplitView` is
the right answer; avoid `HSplitView` (deprecated feel, harder to restore state).

```swift
struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedRepoID: Repo.ID?
    @State private var selectedBranchID: Branch.ID?

    var body: some View {
        NavigationSplitView {
            // Pane 1 — sidebar: repo list
            RepoSidebar(selection: $selectedRepoID)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } content: {
            // Pane 2 — branches for the selected repo
            if let repoID = selectedRepoID, let repo = model.repo(repoID) {
                BranchList(repo: repo, selection: $selectedBranchID)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 260)
            } else {
                ContentUnavailableView("No repo selected",
                    systemImage: "folder.badge.questionmark")
            }
        } detail: {
            // Pane 3 — commit graph / diff
            if let repoID = selectedRepoID, let repo = model.repo(repoID),
               let branchID = selectedBranchID, let branch = repo.branch(branchID) {
                CommitGraphView(repo: repo, branch: branch)
            } else {
                ContentUnavailableView("Select a branch",
                    systemImage: "arrow.triangle.branch")
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}
```

- `ContentUnavailableView` (macOS 14+) is the native empty-state component.
- Column widths persist per window via `navigationSplitViewColumnWidth`.
- The sidebar gets a vibrant background for free — do not override it.

### 2.2 Toolbar conventions

```swift
.toolbar {
    ToolbarItemGroup(placement: .navigation) {
        Button { /* open repo */ } label: {
            Label("Open Repository", systemImage: "folder.badge.plus")
        }
    }
    ToolbarItem(placement: .primaryAction) {
        Button { model.refresh() } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .keyboardShortcut("r", modifiers: .command)
    }
    ToolbarItem(placement: .primaryAction) {
        Menu {
            Button("Fetch") { model.fetch() }
            Button("Pull")  { model.pull()  }
            Button("Push")  { model.push()  }
        } label: {
            Label("Remote", systemImage: "arrow.up.arrow.down")
        }
    }
}
```

Placements: `.navigation` (left), `.primaryAction` (right), `.automatic` (safe
default). Use `Label(_, systemImage:)` on every toolbar button so it renders
correctly when the user switches toolbar mode to Icon/Text Only.

### 2.3 Menu bar commands

```swift
struct GitrubenCommands: Commands {
    let model: AppModel

    var body: some Commands {
        // Replace "New Window" behavior
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { model.newTab() }
                .keyboardShortcut("t", modifiers: .command)
        }

        CommandMenu("Repository") {
            Button("Refresh") { model.refresh() }
                .keyboardShortcut("r", modifiers: .command)
            Button("Fetch")   { model.fetch() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Pull")    { model.pull() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Push")    { model.push() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Divider()
            Button("Open in Terminal") { model.openTerminal() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
        }

        CommandGroup(after: .help) {
            Button("gitruben on GitHub") { /* open URL */ }
        }
    }
}
```

Match Xcode/SourceTree conventions. **Never override ⌘W, ⌘Q, ⌘,** — system-owned.

---

## 3. State management

### 3.1 Use `@Observable`, not `ObservableObject`

Swift 5.9's `@Observable` macro is strictly better than
`ObservableObject`+`@Published`: finer-grained invalidation (only views that
read a property re-render), no `@Published` clutter, works in
`.environment(_:)` without `@EnvironmentObject`.

```swift
import Observation

@Observable
final class AppModel {
    var repos: [Repo] = []
    var selectedRepoID: Repo.ID?

    // Not observed — prefix with @ObservationIgnored for expensive/non-UI state.
    @ObservationIgnored
    private var fsWatcher: FileSystemWatcher?

    func addRepo(at url: URL) { ... }
    func repo(_ id: Repo.ID) -> Repo? { repos.first { $0.id == id } }
}
```

### 3.2 `@State` vs `@Bindable`

- `@State` — owns the value. Use at model-creation site, or for local view
  state (bool flags, text fields, selection).
- `@Bindable` — creates bindings (`$foo`) into an `@Observable` class you do
  not own. Use in children that need to pass bindings down.
- `@Environment(AppModel.self)` — pull from environment. Wrap in `@Bindable`
  to write back.

```swift
struct BranchList: View {
    let repo: Repo                       // @Observable, passed in
    @Binding var selection: Branch.ID?

    var body: some View {
        @Bindable var repo = repo        // local binding wrapper
        List(selection: $selection) {
            ForEach(repo.branches) { branch in
                Text(branch.name).tag(branch.id)
            }
        }
        .searchable(text: $repo.branchFilter)  // two-way binding
    }
}
```

### 3.3 Dependency injection via `.environment()`

```swift
RootView()
    .environment(appModel)
    .environment(\.gitClient, GitClient.shared)
```

Custom environment keys — use the `@Entry` macro (Swift 5.10+):

```swift
extension EnvironmentValues {
    @Entry var gitClient: GitClient = GitClient()
}
```

**[do this]** One `AppModel` owns the list of open repos. Each `Repo` is its
own `@Observable` class owning branches, commits, refresh state. Views receive
`Repo` by parameter.

---

## 4. Async / long-running work

### 4.1 `.task` is the default

`.task` runs when the view appears and is cancelled when it disappears. This
is the correct place for 90% of async loads.

```swift
struct BranchList: View {
    let repo: Repo

    var body: some View {
        List(repo.branches) { ... }
        .task(id: repo.id) {                    // re-runs when repo changes
            await repo.reloadBranches()
        }
    }
}
```

The `id:` overload is crucial — without it, switching from repo A to B does
not re-run the task.

### 4.2 Structured concurrency for multi-step loads

```swift
func reloadAll() async {
    await withTaskGroup(of: Void.self) { group in
        group.addTask { await self.reloadBranches() }
        group.addTask { await self.reloadTags() }
        group.addTask { await self.reloadStatus() }
    }
}
```

### 4.3 Cancellation

`Process` does not integrate with Swift cancellation automatically — you must
wire it up. Pattern:

```swift
func log() async throws -> [Commit] {
    let process = Process()
    // ... configure ...
    try Task.checkCancellation()
    try process.run()
    return try await withTaskCancellationHandler {
        try await readOutput(process)
    } onCancel: {
        process.terminate()   // SIGTERM
    }
}
```

### 4.4 Main actor

`@Observable` classes are **not** main-actor by default. Mark them explicitly:

```swift
@Observable @MainActor
final class Repo { ... }
```

Do heavy work off the main actor (`Task.detached` or `nonisolated` methods
calling `Process`) and hop back only to assign results:

```swift
@MainActor
func reloadBranches() async {
    let branches = await GitClient.listBranches(at: path)  // nonisolated
    self.branches = branches                                // main actor
}
```

---

## 5. Process execution — running `/usr/bin/git`

The most important subsystem of gitruben. Get it right once and reuse.

### 5.1 Core wrapper

```swift
import Foundation

struct GitResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    var isSuccess: Bool { exitCode == 0 }
}

enum GitError: Error, LocalizedError {
    case nonZeroExit(code: Int32, stderr: String)
    case launchFailed(Error)
    case cancelled
}

enum Git {
    static let executable = URL(fileURLWithPath: "/usr/bin/git")

    static func run(
        _ args: [String],
        in workingDirectory: URL,
        environment: [String: String]? = nil
    ) async throws -> GitResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        process.currentDirectoryURL = workingDirectory

        // Inherit PATH so git can find helpers (git-lfs, git-credential-*).
        var env = ProcessInfo.processInfo.environment
        // Force English output for reliable parsing.
        env["LC_ALL"] = "C"
        env["LANG"]   = "C"
        // Don't let git prompt — if it needs creds, fail fast.
        env["GIT_TERMINAL_PROMPT"] = "0"
        if let extra = environment { env.merge(extra) { _, new in new } }
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError  = errPipe
        process.standardInput  = FileHandle.nullDevice

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                process.terminationHandler = { proc in
                    let out = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                    let err = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                    cont.resume(returning: GitResult(
                        stdout: String(decoding: out ?? Data(), as: UTF8.self),
                        stderr: String(decoding: err ?? Data(), as: UTF8.self),
                        exitCode: proc.terminationStatus
                    ))
                }
                do {
                    try process.run()
                } catch {
                    cont.resume(throwing: GitError.launchFailed(error))
                }
            }
        } onCancel: {
            process.terminate()
        }
    }

    /// Convenience: throw on non-zero exit.
    static func check(
        _ args: [String], in cwd: URL, env: [String: String]? = nil
    ) async throws -> String {
        let r = try await run(args, in: cwd, environment: env)
        guard r.isSuccess else {
            throw GitError.nonZeroExit(code: r.exitCode, stderr: r.stderr)
        }
        return r.stdout
    }
}
```

### 5.2 Streaming output (for long operations)

For `git fetch`/`clone`/`push`, stream progress rather than wait for exit:

```swift
static func stream(
    _ args: [String], in cwd: URL
) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        process.currentDirectoryURL = cwd

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = pipe   // merge; git writes progress to stderr

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            if let s = String(data: data, encoding: .utf8) {
                continuation.yield(s)
            }
        }
        process.terminationHandler = { proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            if proc.terminationStatus == 0 {
                continuation.finish()
            } else {
                continuation.finish(throwing: GitError.nonZeroExit(
                    code: proc.terminationStatus, stderr: ""))
            }
        }

        do {
            try process.run()
        } catch {
            continuation.finish(throwing: GitError.launchFailed(error))
        }

        continuation.onTermination = { @Sendable _ in
            if process.isRunning { process.terminate() }
        }
    }
}
```

Consume:

```swift
for try await chunk in Git.stream(["fetch", "--progress", "origin"], in: repo.url) {
    model.fetchLog.append(chunk)
}
```

### 5.3 Parsing tips

- `git log --format=%H%x1f%P%x1f%an%x1f%at%x1f%s%x1e` uses ASCII unit/record
  separators (`0x1f`/`0x1e`). Safer than whitespace splitting.
- `--no-pager` is automatic when stdout is not a TTY (free via `Process`).
- `-z` for null-terminated `git status`, `git ls-files`, `git diff --name-only`.
- `--porcelain=v2` for `git status`. V1 is fragile.

### 5.4 Finding git

`/usr/bin/git` is a shim for Xcode CLT; if not installed, it pops a GUI
prompt. For a personal tool, assume CLT is installed. If you want to be
robust, check `/opt/homebrew/bin/git`, `/usr/local/bin/git`, `/usr/bin/git`
in order via `FileManager.isExecutableFile`.

---

## 6. File system watching

When the user runs `git commit` in a terminal, the UI should update.

### 6.1 FSEvents (recommended for repo trees)

`FSEventStream` watches a directory tree via coalesced kernel events. C API,
usable from Swift:

```swift
import CoreServices

final class RepoWatcher {
    private var stream: FSEventStreamRef?
    private let callback: @Sendable () -> Void

    init(url: URL, callback: @escaping @Sendable () -> Void) {
        self.callback = callback
        start(url: url)
    }

    deinit { stop() }

    private func start(url: URL) {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)

        let paths = [url.path] as CFArray
        let flags: FSEventStreamCreateFlags =
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, count, _, _, _ in
                guard let info else { return }
                let me = Unmanaged<RepoWatcher>.fromOpaque(info).takeUnretainedValue()
                me.callback()
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,                // 500ms coalescing
            flags)

        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
    }

    private func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
    }
}
```

Watch the **repo root**, not `.git/` — you want working-tree *and* refs
changes. Debounce in your model.

### 6.2 `DispatchSourceFileSystemObject`

For a single file (e.g. `.git/HEAD`). Lighter than FSEvents, no recursion:

```swift
let fd = open(path, O_EVTONLY)
let source = DispatchSource.makeFileSystemObjectSource(
    fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
source.setEventHandler { callback() }
source.setCancelHandler { close(fd) }
source.resume()
```

**[do this]** FSEvents on the repo root, one watcher per open repo.

---

## 7. Persistence

Persisted state is tiny: pinned/recent repos, preferences (diff font, tab
size, theme). Window geometry is automatic.

**[do this]** `UserDefaults` + `Codable` under a single key. SwiftData is for
10k+ records with relationships — wrong tool for "20 paths."

```swift
struct PinnedRepo: Codable, Identifiable, Hashable {
    let id: UUID
    var path: String
    var alias: String?
    var lastBranch: String?
}

@propertyWrapper
struct CodableDefault<T: Codable> {
    let key: String
    let defaultValue: T

    var wrappedValue: T {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let value = try? JSONDecoder().decode(T.self, from: data)
            else { return defaultValue }
            return value
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

@Observable @MainActor
final class AppModel {
    @ObservationIgnored
    @CodableDefault(key: "pinnedRepos", defaultValue: [])
    private var _pinned: [PinnedRepo]

    var pinned: [PinnedRepo] {
        get { _pinned }
        set { _pinned = newValue }
    }
}
```

For caches that should not live in prefs (commit cache, parsed graph), write
to `~/Library/Application Support/gitruben/` via `FileManager`. Do not stuff
SQLite into UserDefaults.

### AppStorage for scalars

For bools/ints/strings, `@AppStorage("key")` is the one-liner:

```swift
@AppStorage("diffFontSize") private var diffFontSize: Double = 12
@AppStorage("useRelativeDates") private var useRelativeDates = true
```

---

## 8. SF Symbols for git

Install Apple's free **SF Symbols** app to search. Core vocabulary:

| Concept | Symbol |
| --- | --- |
| Branch | `arrow.triangle.branch` |
| Merge | `arrow.triangle.merge` |
| Pull request | `arrow.triangle.pull` |
| Commit (generic) | `circle.fill` or `smallcircle.filled.circle` |
| Tag | `tag` / `tag.fill` |
| Remote / cloud | `cloud` / `icloud` / `network` |
| Fetch | `arrow.down.circle` |
| Pull | `arrow.down` |
| Push | `arrow.up` |
| Refresh | `arrow.clockwise` |
| Sync (both) | `arrow.triangle.2.circlepath` |
| Stash | `tray.and.arrow.down` / `archivebox` |
| Diff / changes | `plusminus` or `doc.on.doc` |
| Untracked file | `questionmark.circle` |
| Modified | `pencil.circle` |
| Staged | `plus.circle.fill` |
| Deleted | `minus.circle.fill` |
| Conflict | `exclamationmark.triangle.fill` |
| HEAD / current | `arrowtriangle.right.fill` |
| Repo | `folder` / `externaldrive` |
| Terminal | `terminal` |
| Settings | `gearshape` |
| Clone | `square.and.arrow.down` |

Use as `Label("Fetch", systemImage: "arrow.down.circle")`. Color via
`.foregroundStyle(.tint)`. Defer custom icons until needed.

---

## 9. Rendering a commit graph

The hard view. Approach that scales:

### 9.1 Architecture

1. **Compute layout off the main thread.** Given topologically-ordered
   commits + parent SHAs, produce `[CommitRow]` with `laneIndex` and
   `edgesToDraw`. Pure function — easy to unit-test.
2. **Virtualize rows** via `List` or `LazyVStack`. Over ~500 commits, `List`
   wins (it uses `NSTableView`).
3. **Draw the graph column with `Canvas`** — one `Canvas` per row, fixed
   width, drawing dots + edges entering/leaving that row.

### 9.2 Row-local canvas (simplest, scales fine)

```swift
struct GraphCell: View {
    let row: CommitRow
    let laneColors: [Color]
    private let laneWidth: CGFloat = 16
    private let dotRadius: CGFloat = 5

    var body: some View {
        Canvas { ctx, size in
            let midY = size.height / 2

            // Draw edges passing through / entering this row
            for edge in row.edges {
                let x1 = CGFloat(edge.fromLane) * laneWidth + laneWidth / 2
                let x2 = CGFloat(edge.toLane)   * laneWidth + laneWidth / 2
                let y1 = edge.startsHere ? midY : 0
                let y2 = edge.endsHere   ? midY : size.height

                var path = Path()
                path.move(to: CGPoint(x: x1, y: y1))
                if x1 == x2 {
                    path.addLine(to: CGPoint(x: x2, y: y2))
                } else {
                    // Smooth curve across lanes
                    let midpointY = (y1 + y2) / 2
                    path.addCurve(
                        to: CGPoint(x: x2, y: y2),
                        control1: CGPoint(x: x1, y: midpointY),
                        control2: CGPoint(x: x2, y: midpointY))
                }
                ctx.stroke(path,
                           with: .color(laneColors[edge.color % laneColors.count]),
                           lineWidth: 2)
            }

            // Draw the dot
            let dotX = CGFloat(row.lane) * laneWidth + laneWidth / 2
            let rect = CGRect(x: dotX - dotRadius, y: midY - dotRadius,
                              width: dotRadius * 2, height: dotRadius * 2)
            ctx.fill(Path(ellipseIn: rect),
                     with: .color(laneColors[row.lane % laneColors.count]))
        }
        .frame(width: CGFloat(row.maxLane + 1) * laneWidth, height: 28)
    }
}

struct CommitGraphView: View {
    let rows: [CommitRow]

    var body: some View {
        List(rows) { row in
            HStack(spacing: 8) {
                GraphCell(row: row, laneColors: Self.palette)
                Text(row.shortSHA).font(.system(.body, design: .monospaced))
                Text(row.subject).lineLimit(1)
                Spacer()
                Text(row.relativeDate).foregroundStyle(.secondary)
            }
        }
    }

    static let palette: [Color] = [.blue, .green, .orange, .purple,
                                   .pink, .teal, .yellow, .red]
}
```

### 9.3 Tradeoffs and perf

- `Canvas` is immediate-mode; re-draws every layout pass. Fine for tiny
  row-local canvases.
- A single tall `Canvas` covering the whole graph is simpler but breaks row
  virtualization. Avoid.
- For 100k+ commits, precompute lane assignment incrementally and page.
- `Image(systemName:)` with `.resizable()` inside rows needs a fixed frame.
- `List(selection:)` + `.tag(id)` gives ⌘-click multi-select and arrow keys
  for free.

---

## 10. Testing

### 10.1 Unit tests — prefer Swift Testing

**Swift Testing** is the Xcode 16 default: expressive `#expect` macros, no
test class boilerplate, built-in parameterized tests. Use it for pure Swift
logic.

```swift
import Testing
@testable import gitruben

@Suite("Git log parser")
struct GitLogParserTests {
    @Test("parses a single commit with separator format")
    func singleCommit() throws {
        let input = "abcd1234\u{1f}parentabc\u{1f}Ruben\u{1f}1700000000\u{1f}fix thing\u{1e}"
        let commits = try GitLogParser.parse(input)
        #expect(commits.count == 1)
        #expect(commits[0].sha == "abcd1234")
        #expect(commits[0].authorName == "Ruben")
    }

    @Test("handles merges with multiple parents",
          arguments: [
            ("a b c", ["a","b","c"]),
            ("", []),
            ("a", ["a"])
          ])
    func parentParsing(raw: String, expected: [String]) {
        #expect(GitLogParser.parseParents(raw) == expected)
    }
}
```

### 10.2 Snapshot tests

Use **pointfreeco/swift-snapshot-testing** (SPM). It uses XCTest. Keep
snapshot tests in a separate target so first-run writes do not block the
unit suite.

```swift
import SnapshotTesting
import SwiftUI
import XCTest

final class CommitGraphSnapshotTests: XCTestCase {
    func test_linearHistory() {
        let view = CommitGraphView(rows: .fixtureLinear)
            .frame(width: 800, height: 600)
        let host = NSHostingController(rootView: view)
        assertSnapshot(of: host, as: .image)
    }
}
```

First run: tests "fail" and write PNGs to `__Snapshots__/`. Commit them.

### 10.3 What to test

- **Parsers** — 100% coverage. Bugs hide here.
- **Graph layout** — property-based: for any DAG, no crossed edges within a
  lane, HEAD in lane 0, etc.
- **View snapshots** — 5-10 canonical scenes (empty state, diamond merge,
  conflict row). Do not snapshot every view.

Do **not** run `Process`-based integration tests in CI; flaky. Mock
`GitClient` behind a protocol for view-model tests.

---

## 11. Common gotchas

### 11.1 Main actor

- `@Observable` properties driving UI must be mutated on the main actor.
  Making the class `@MainActor` lets the compiler enforce it.
- `Process.terminationHandler` fires on a background queue. Hop back to main
  before assigning observed state.
- `Task { }` in a view inherits the view actor (main); `Task.detached` does
  not. Use detached for CPU-heavy parsing, plain `Task` for orchestration.

### 11.2 Sandbox / file system

- `Process.currentDirectoryURL` must point to an **existing** directory or
  `run()` throws `NSPOSIXErrorDomain 2` (ENOENT).
- `URL(fileURLWithPath:)` does not expand `~` — use
  `(path as NSString).expandingTildeInPath` or
  `FileManager.default.homeDirectoryForCurrentUser`.
- If you later enable sandbox, every repo path needs a security-scoped
  bookmark persisted as `Data`; call `startAccessingSecurityScopedResource()`
  before every `Process` call.
- "Full Disk Access" (System Settings) is a separate layer — needed only to
  read repos inside `~/Library/` without consent dialogs.

### 11.3 `Process` specifics

- **Never** `Process.launch()` — deprecated. Use `run()`.
- Set `standardInput = FileHandle.nullDevice` or the child may hang on
  inherited stdin.
- `terminate()` sends SIGTERM; some git ops ignore it briefly. If needed,
  follow up with `Darwin.kill(pid, SIGKILL)` after a 2s grace.
- `readDataToEndOfFile()` on the calling thread deadlocks if the child fills
  both stdout and stderr buffers. Read both pipes concurrently (via
  `terminationHandler` + `readToEnd()` or `readabilityHandler`).

### 11.4 SwiftUI specifics

- Do not strongly capture `self` inside `.task { }` — the view is a value
  type; capture model references explicitly.
- `List` selection tags must be `Hashable` and the selection state type must
  match exactly (including optionality).
- `@State` of a class is stable across view re-creation; `@State` of a
  struct is not. Use classes for identity.
- `onChange(of:)` on macOS 14+ uses the two-parameter closure
  `(oldValue, newValue)`.

### 11.5 Xcode preview quirks

- Use `#Preview { ... }`, not `PreviewProvider`. Provide a
  lightweight init for previews or they time out.
- `Process` calls crash previews. Gate with
  `ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"`.

---

## 12. Build & distribution for personal use

No Apple Developer account, no intent to ship. Goal: a `gitruben.app` you
drag to `/Applications` and launch without warnings.

### 12.1 Sign to Run Locally

In **Signing & Capabilities**: Team *None*, Signing Certificate **Sign to
Run Locally** (ad-hoc, uses `codesign -s -`). App runs on *your* machine;
copying to another Mac triggers Gatekeeper (right-click → Open the first
time).

### 12.2 Hardened Runtime — off

For local signing, leave Hardened Runtime off. Enabling it requires
entitlements like `com.apple.security.cs.disable-library-validation` or
`Process`-spawned git launches fail in strange ways. Not worth it.

### 12.3 Building

**Xcode**: Product → Archive → **Distribute App → Custom → Copy App →
Export**.

**CLI** (reproducible):

```bash
xcodebuild \
  -scheme gitruben \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  clean build

# App is at:
#   build/Build/Products/Release/gitruben.app
ditto build/Build/Products/Release/gitruben.app /Applications/gitruben.app
```

Commit this as `scripts/build.sh`.

### 12.4 DMG (optional)

For installing on a second Mac. `create-dmg` is the least painful path:

```bash
brew install create-dmg

create-dmg \
  --volname "gitruben" \
  --window-size 540 380 \
  --icon-size 96 \
  --icon "gitruben.app" 140 180 \
  --app-drop-link 400 180 \
  --hide-extension "gitruben.app" \
  "gitruben.dmg" \
  "build/Build/Products/Release/gitruben.app"
```

The DMG is **not** notarized. On another Mac, Gatekeeper will warn;
workaround with `xattr -cr gitruben.app` or right-click → Open. Notarization
requires a paid Developer account — defer.

### 12.5 Login items / menu bar extras

Out of scope for v1. When needed: `ServiceManagement.SMAppService` (macOS
13+). Do not touch launchd plists by hand.

---

## Quick-reference checklist for v1

- [ ] Xcode 16/26 macOS App template, SwiftUI, Testing: Swift Testing.
- [ ] Sandbox OFF, Hardened Runtime OFF, Sign to Run Locally.
- [ ] `GitrubenApp` with `WindowGroup` + `Settings` + `Commands`.
- [ ] `RootView` using `NavigationSplitView` three-column.
- [ ] `AppModel` (`@Observable @MainActor`) in `.environment`.
- [ ] `Repo` (`@Observable @MainActor`) owned by AppModel.
- [ ] `Git.run` / `Git.stream` wrappers around `/usr/bin/git`.
- [ ] `LC_ALL=C`, `GIT_TERMINAL_PROMPT=0`, `stdin=nullDevice` on every call.
- [ ] `FSEventStream` watcher per open repo, 500ms coalescing.
- [ ] Pinned repos persisted via `UserDefaults` + `Codable`.
- [ ] `Canvas`-based `GraphCell` inside a `List` for commit history.
- [ ] Unit tests (Swift Testing) for parsers; snapshot tests for key views.
- [ ] `scripts/build.sh` that does ad-hoc signed release builds.

Build vertical slices: get "show branches for one hard-coded repo" working
end-to-end before generalizing. SwiftUI rewards iteration; abstractions made
up front are almost always wrong.
