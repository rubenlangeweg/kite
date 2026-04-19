# Git Graph Rendering — Research Artifact

Rendering the "branch tree" DAG that GitKraken, Fork, Sourcetree, and GitLab
show alongside commit history. Target: SwiftUI, ~200 commits across all
branches, vertical lanes, colored branches, dots for commits, lines for
parent relationships, smooth scroll.

This doc covers: layout algorithms, edge routing, color assignment, the
SwiftUI rendering strategy, row content, ref labels, performance, references,
failure cases, and the minimum viable v1 to ship.

---

## 1. The Layout Problem

**Input**
- An ordered list of commits (reverse-topo: newest at top, parents after
  children on the wire but below them on screen).
- Each commit has a stable hash and 0..N parent hashes (0 = root, 1 = normal,
  2 = merge, 3+ = octopus).

**Output**
- For each commit, a `lane` integer (column 0..K). Lane 0 is leftmost.
- Incoming edges (from already-placed children) and outgoing edges (to
  not-yet-placed parents) with source lane, target lane, and the row they
  span.
- A lane count K so the UI can reserve width = `K * laneWidth + padding`.

The challenge: parents are reached via multiple children (branches diverge)
and children have multiple parents (merges converge). We want to (a) minimize
lane count, (b) keep linear chains in a single column, (c) stay stable when
the user scrolls or fetches.

### ASCII of the target output

```
  *     abc123  add login screen          (HEAD, main)
  |\
  | *   def456  fix button padding         (feature/auth)
  | *   789abc  wire OAuth provider
  |/
  *     111aaa  bump version
  *     222bbb  tidy README
  |\
  | *   333ccc  hotfix: null ref           (hotfix/null-ref)
  |/
  *     444ddd  initial commit
```

Three lanes at peak. Merge on row 1 collapses lane 1 back into lane 0. Row 5
does the same. Linear chain stays in lane 0 throughout.

### Algorithm options

**(a) Naive — one column per branch tip.** For each ref, allocate a column;
walk that branch's history inside it; draw merges as diagonals between
columns. Pros: trivial, stable per-branch color. Cons: 30 branches → 30
columns, most empty for most rows. Never reuses a column after merge-back.
Unusable beyond toy repos.

**(b) Column reuse.** Walk commits top-down, maintain an `active[]` array
where `active[i]` = the commit hash each lane is waiting for. When we reach
a commit, find which lane was waiting for it (that becomes its lane; free
other lanes waiting on the same hash — they were redundant branches merging
in). Place parents into lanes: first parent keeps the current lane; others
join existing waiting lanes or allocate fresh. Reuse nil holes when
allocating. This is what `git log --graph`, git-graph (Rust), GitLab, and
Fork use.

**(c) Straight-line prioritization.** Refinement on (b): when a commit has
multiple parents, route the first parent into the same column (git itself
treats first-parent as the mainline for `--first-parent`). Merged-in parents
go to other columns. Result: `main` stays in lane 0 through history instead
of zig-zagging every time a feature branch merges in.

### Recommended: column reuse + first-parent preference

Pseudocode:

```
function layout(commits):                    # newest first
    lanes = []                               # lanes[i] = expected-hash or nil
    rows  = []

    for commit in commits:
        # 1. Find or assign this commit's lane.
        lane = indexOf(lanes, commit.hash)
        if lane == nil:
            lane = firstFreeSlot(lanes)      # reuse nil hole, else append
        lanes[lane] = nil                    # consume

        # 2. Other lanes waiting for the SAME commit (merge reached via
        #    multiple children) — record as incoming, free them.
        mergedFrom = []
        for i, expected in enumerate(lanes):
            if expected == commit.hash:
                lanes[i] = nil
                mergedFrom.append(i)

        # 3. Place parents.
        #    First parent: stay in this lane (keep linear chains straight).
        #    Others: join an existing waiting lane, or allocate a new slot.
        parentLanes = []
        for pIdx, parent in enumerate(commit.parents):
            existing = indexOf(lanes, parent)
            if existing != nil:
                parentLanes.append(existing)      # join existing lane
                continue
            if pIdx == 0:
                lanes[lane] = parent
                parentLanes.append(lane)
            else:
                slot = firstFreeSlot(lanes)
                lanes[slot] = parent
                parentLanes.append(slot)

        rows.append({
            commit, lane, mergedFrom, parentLanes,
            lanesAfter: lanes.copy(),             # for through-lane drawing
        })

    return rows, maxLaneCount(rows)

function firstFreeSlot(lanes):
    for i, v in enumerate(lanes):
        if v == nil: return i
    lanes.append(nil)
    return lanes.count - 1
```

Complexity: O(N * L). 200 commits × ~10 peak lanes = ~2000 ops, microseconds.

Subtle details:
- Root commits (0 parents): after step 1, simply leave the lane freed.
- Octopus (>2 parents): treat all beyond the first as new/joining lanes. Edges
  won't look beautiful but stay correct.
- Stable lane assignment requires stable input order. Use commit time as the
  topo-order tiebreaker so lanes don't shuffle when the user fetches.

The `lanesAfter` snapshot is essential for rendering: each row needs to know
which columns have through-lanes (branches passing this row with no commit)
so it can draw plain verticals at those x-positions.

---

## 2. Edge Routing

Each row draws:
- **The commit dot** at `(lane * laneWidth + laneWidth/2, rowHeight/2)`.
- **Incoming edges**: for each lane in `mergedFrom` plus the commit's own
  lane, a line from the row's top edge converging on the dot.
- **Outgoing edges**: for each `parentLane`, a line from the dot to the row's
  bottom edge at that lane's x.
- **Through-lane edges**: for every lane in both `lanesBefore` and
  `lanesAfter` with no commit on this row, a plain vertical top-to-bottom at
  that lane's x.

### Line shapes

Same lane top-to-bottom: straight vertical segment.

Lane switch (merge or fork): the simplest good-enough shape is a
three-segment path — vertical from top-edge down to ~40% height at source x,
diagonal to ~60% height at target x, vertical to bottom-edge at target x.
This is an S-shape and mirrors what `git log --graph` approximates with
`| \` / `| /`. Cheap, reads cleanly.

For v2 polish, replace the middle diagonal with a cubic Bezier:
`P0=(srcX, 0.4h)`, `C1=(srcX, 0.5h)`, `C2=(dstX, 0.5h)`, `P1=(dstX, 0.6h)`.
The GitKraken look. Tiny perf cost, softer visual.

### Octopus merges (>2 parents)

Real but rare (Linux kernel, some subtree merges). For v1: draw straight
lines from the commit dot to each parent lane; don't try to curve them. Users
will see a minor visual spike if present, but correctness holds.

### Why per-row edges tile cleanly

All edges enter a row at `y=0` and exit at `y=rowHeight`, always centered on
`lane * laneWidth + laneWidth/2`. That means row N's bottom exits line up
exactly with row N+1's top entries. No global coordination needed.

---

## 3. Color Assignment

Goals: stable across refreshes, distinct, tied to branch identity rather than
lane index.

**(a) By lane index.** `palette[lane % palette.count]`. Breaks stability the
moment a new lane appears on the left.

**(b) By branch name hash.** Resolve each lane to the branch it terminates
at; hash the ref name into the palette.
```
color(lane) = palette[fnv1a(branchName(lane)) % palette.count]
```
Stable across fetches. Collisions possible — with 8 palette entries and 5
visible branches there's ~50% chance two share a color. Live with it for v1.

**(c) Creation-order with persistence.** Each new lane gets the next palette
color; persist `{branchName: colorIndex}` so the next launch uses the same
mapping. What GitKraken and Fork do. Ship this in v2.

**Palette** — 6 colors, reasonable hue spacing, medium saturation, readable
on both light and dark:

```
#4A90E2  blue     (primary / main)
#7B61FF  purple
#00A884  green
#E07A5F  orange
#D14670  red
#B8860B  amber
```

Always hardcode `main` / `master` / `trunk` to blue, regardless of hash.

---

## 4. SwiftUI Rendering: Canvas vs CAShapeLayer vs per-row

**(a) One giant Canvas for the whole graph.** Width `K * laneWidth`, height
`N * rowHeight`, wrapped in a ScrollView. Simple coords. No virtualization —
fine for 200, bad for 20,000.

**(b) CAShapeLayer per edge + layer per dot.** GPU-cached paths, free scroll
once built. Needs `NSViewRepresentable` bridging, sublayer count grows
linearly, reuse is manual. Complexity not worth it.

**(c) Per-row Canvas inside a List row — RECOMMENDED.** Each row is an
`HStack`:
- A fixed-width `Canvas` (`K * laneWidth` × `rowHeight`) that draws only this
  row's slice — through-lanes, incoming, dot, outgoing.
- The commit content (message, refs, author, age).

Wrap in a SwiftUI `List` (or `LazyVStack` if List styling is too opinionated).
SwiftUI virtualizes — only visible rows exist. Each row's Canvas closure
draws 4-10 short paths.

Why this wins:
- **Virtualization free**: offscreen rows drop out.
- **Self-contained rows**: each row is stateless over layout; input is the
  prebuilt `LayoutRow`, output is pixels.
- **Scroll cheap**: SwiftUI recycles row views; redrawing 6 visible rows on
  scroll is nothing.
- **Pure SwiftUI**: no AppKit bridging.

Sketch:

```swift
struct GraphRow: View {
    let row: LayoutRow
    let palette: [Color]
    let laneWidth: CGFloat = 14
    let rowHeight: CGFloat = 28

    var body: some View {
        HStack(spacing: 8) {
            Canvas { ctx, size in
                drawThroughLanes(&ctx, row, palette, laneWidth, rowHeight)
                drawIncomingEdges(&ctx, row, palette, laneWidth, rowHeight)
                drawOutgoingEdges(&ctx, row, palette, laneWidth, rowHeight)
                drawDot(&ctx, row, palette, laneWidth, rowHeight)
            }
            .frame(width: CGFloat(row.totalLanes) * laneWidth,
                   height: rowHeight)

            CommitRowContent(commit: row.commit)
        }
        .frame(height: rowHeight)
    }
}
```

All draw helpers are pure functions over `row`. No view state.

---

## 5. Commit Row Content

Layout, left-to-right:

```
[ graph canvas ] [ message                    ] [ refs ] [ author ] [ age ]
  ~K*14 fixed     flex, truncate tail           auto     120pt      60pt
```

Tips:
- **Fixed widths on right columns** (author, age) so the message flexes
  predictably and refs can float next to the message.
- **Truncate message tail**: `lineLimit(1)`, `truncationMode(.tail)`. Never
  wrap — breaks vertical rhythm.
- **Age**: compact relative time (`3m`, `2h`, `4d`, `1mo`, `2y`). Drive it
  off a shared `TimelineView(.periodic(by: 60))` at the top so the whole list
  re-renders once per minute — no per-row timers.
- **Selection highlight** spans all columns including the graph canvas, so
  keep the canvas background transparent.
- **Row height**: 28pt feels right. Too tall → sparse graph; too short →
  cramped text.
- **Short hash** (7 chars) in monospace, if shown.

---

## 6. Ref Labels (Branch / Tag Pills)

Pills adjacent to the commit message, colored by type:

- **Local branches**: solid fill in lane color, white text, 2pt radius.
  - `HEAD` / current branch: heavier weight or outline ring.
- **Remote branches** (`origin/main`): lighter fill, secondary text, often
  muted next to the local counterpart.
- **Tags**: different shape (flag / pentagon) or tag icon prefix, amber/gold
  fill.
- **Detached HEAD**: red accent pill with `HEAD` text.
- Cap at **3-4 visible**; beyond that, collapse into `+2` with a hover
  popover.

Layout: pills immediately after the message, before the author column.
Styling: `padding(h: 6, v: 2)`, `cornerRadius(3)`, `.caption.monospaced()`.
Truncate ref name beyond ~20 chars.

**For v1, ship branch pills only** (local + remote). Defer tag pills to v2 —
tags are rarely viewed day-to-day and their styling can wait.

---

## 7. Performance

200 commits is trivial; plan for 20k even if we don't hit it in v1.

**Fast already.** Layout O(N*L): 20k × 20 = 400k ops, sub-ms in Swift if the
inner loop is allocation-free. Rendering: per-row Canvas only runs for
visible rows. Scroll cost is O(rows on screen), not O(N).

**Can get slow.**
- **Re-layout on every fetch.** Compute once, cache. New commits always
  arrive at the top, so layout can be incremental — run on the new prefix,
  stitch into the existing `lanesAfter` state at the joint.
- **Per-row ref resolution.** Building `{commitHash: [refs]}` every frame is
  wasteful. Build once at repo load, invalidate on ref changes.
- **Age formatting.** Don't update 200 rows/second. Use top-level
  `TimelineView(.periodic(by: 60))`.

**Background actor.**

```swift
actor GraphLayoutEngine {
    private var cache: [RepoID: LayoutResult] = [:]

    func layout(repo: RepoID, commits: [Commit]) async -> LayoutResult {
        if let hit = cache[repo], hit.matchesHead(of: commits) { return hit }
        let result = computeLayout(commits)        // pure function
        cache[repo] = result
        return result
    }
}
```

The view observes via `@Observable`. First paint shows the previous graph or
a skeleton; swap when layout finishes. For 200 commits this completes in ~1ms
so the user never sees the skeleton — the architecture is ready for 20k.

**Viewport rendering.** Beyond a few thousand commits even `LazyVStack`
struggles with outer container height. At that point, render a window of rows
around the visible area with absolute offsets (UITableView/NSTableView
territory). Not needed for v1.

---

## 8. Known-Good References

**`git log --graph`** — the baseline. `git/builtin/log.c` plus `graph.c`. Uses
column reuse with first-parent preference. ASCII characters `*`, `|`, `/`,
`\`, `_` compose the graph. Worth reading `graph.c` before implementing — it
maps directly to an on-screen renderer.

**git-graph (Rust crate)** — `github.com/mlange-42/git-graph`. SVG and
terminal output, multiple branching models (`simple`, `git-flow`, custom). A
few thousand lines, open-source. Core abstraction: assign each commit to a
branch, then lay branches out in columns. Useful reference for the
branch-name-to-column mapping we should adopt for stable colors.

**GitKraken** — polished: bezier curves, sticky per-branch colors, WebGL on
canvas. Lanes widen on hover; commit dots have halos. Aggressive "main in
column 0" invariant — pushes other lanes right to preserve it.

**Fork (macOS)** — straight-segment-with-diagonal edges (not beziers), ~14pt
lanes, solid colored dots. Very readable at density. Close to what we should
ship for v1 — prettier than `git log --graph` but without GitKraken's
bezier expense.

**Sourcetree** — beziers with heavier stroke. Tends to allocate more columns
than Fork (more spread out). Branches colored by hash.

**gitgraph.js / @gitgraph/react** — `github.com/nicoespeon/gitgraph.js`.
D3-adjacent, used in docs and blog posts. Good SVG edge-routing demos.
Imperative API (describe commits + branches, it renders). Layout lives in
`@gitgraph/core/src/user-api/branch.ts`. Cleaner than GitKraken's approach.

**Mermaid `gitGraph`** — similar column reuse with first-parent preference.
Useful for docs, not a code reference.

---

## 9. Failure Cases

**Shallow clones / disconnected history.** `git clone --depth=200` ends with
a "fake" root: the deepest commit references parents not in the repo. Our
algorithm will keep lanes open for those phantom parents forever. Detect via
`.git/shallow` and render a truncation indicator — dashed trailing line at
the bottom or a "fetch more" footer.

**200 commits mid-merge-storm.** A release train with 30+ feature merges in
the window spikes peak lane count. The graph gets wide. Options: soft-cap at
10 visible lanes with a "+3" indicator, or let the user horizontally scroll
the graph column (keep the message column fixed).

**Many parallel feature branches.** Same problem sustained. Straight-line
prioritization keeps `main` in lane 0 but width still blows up. Real answer:
filters ("hide branches inactive >30 days"). Out of scope for v1 layout, in
scope for v1.5 UI.

**Reorders on fetch.** If incoming commits have commit times earlier than
existing ones (rebases, cherry-picks), topo order shifts. For 200 commits
just recompute — cheap and bug-free.

**First-parent ambiguity in octopus merges.** Only parent 1 stays in lane;
parents 2..N allocate. Visually fine. Git itself doesn't promise which "real"
branch parents 2 vs 3 correspond to.

**Force-pushed branches.** Orphaned commits still reachable from reflog but
not any ref tip. No special-case: they appear in the commit list or not
depending on what we fetch.

---

## 10. Minimum Viable Visualization for v1

### In scope

- **Column-reuse layout** with first-parent preference.
- **Lane colors via branch-name hash**, 6-color palette, `main` hardcoded
  blue.
- **Straight + diagonal edges** (no beziers). Three-segment paths.
- **Per-row SwiftUI Canvas** inside a `List`. Dot radius 4pt, lane width
  14pt, row height 28pt.
- **Commit row**: graph | message (truncate) | branch pills | author initials
  | relative age.
- **Branch pills only** (local filled, remote outlined/muted). `HEAD`
  indicator via outline/weight.
- **200 commit hard limit** on query; layout computed once per fetch on a
  background actor; cached until refs change.
- **Shallow-clone truncation indicator** (dashed trailing line).

### Deferred to v2

- Bezier edge smoothing.
- Tag pills (separate shape / color).
- Persistent sticky colors across launches.
- Octopus merge beautification.
- Horizontal lane collapse ("+3 lanes hidden").
- Incremental re-layout on fetch.
- Hover-expand lanes.
- Search / filter affecting the graph.
- Viewport-only rendering for 10k+ repos.

### Done-looks-like

User opens a repo with 3 active branches including a recent merge. Within
~100ms they see:
- 200 rows.
- Blue line down the left (main).
- Purple branching off mid-way, 3 commits, merging back.
- Green branching further down.
- Blue pill `main` at HEAD, muted blue `origin/main` beside it, purple
  `feature/auth` on the branch tip.
- Scroll is butter-smooth — each row is cheap.

That beats every "flat list of commits" view and gets us 80% of the way to
GitKraken-level polish for 20% of the effort. v2 closes the gap.

---

## Appendix A: Row Struct

The layout output per row. Kept small so many rows fit in memory.

```swift
struct LayoutRow {
    let commit: Commit              // hash, message, author, date, parents, refs
    let lane: Int                   // this commit's column
    let mergedFromLanes: [Int]      // incoming edges converging from above
    let parentLanes: [Int]          // outgoing edges (index-aligned to parents)
    let lanesAfter: [Int?]          // lane state AFTER this row (for through-lanes)
    let totalLanes: Int             // max(lanesAfter.count, lane+1)
}
```

200 rows is a few KB total. Cheap to recompute, cheap to cache.

## Appendix B: Draw Order Per Row

Later draws paint over earlier:

1. Through-lane vertical segments (branches passing by).
2. Incoming edges (converging to this row's dot from above).
3. Outgoing edges (diverging to below).
4. The commit dot (filled circle, with a ring for HEAD / merge).

Dots last so they sit on top of their own edges — otherwise lines poke
through the dot and it looks sloppy.
