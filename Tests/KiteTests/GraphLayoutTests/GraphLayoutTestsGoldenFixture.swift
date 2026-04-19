import Foundation
@testable import Kite

/// Canonical hand-built DAG used for the M4-graph-layout golden-fixture
/// test (VAL-GRAPH-002). The shape mixes every structural case the layout
/// algorithm has to handle:
///
///   - Linear first-parent chain on main (A → B → D → F → M).
///   - Feature branch merge back to main (C merges into E).
///   - Merge commit on main consuming both main and feature (E, M).
///   - Detached orphan chain with its own root (X → Y → Z).
///   - Octopus merge with 3 parents (O consuming F, D, C).
///   - Isolated root (P).
///
/// Topo order is newest-first, with the orphan chain and octopus placed
/// after M but before the main-line ancestors — matching the output shape
/// `git log --all --topo-order` produces when the DAG has multiple roots.
///
/// The expected layout lives at `Fixtures/goldenFixture.json` next to this
/// file. To regenerate it (only with explicit scrutiny approval), delete the
/// JSON file and re-run the suite; `loadReference()` writes a fresh copy when
/// none exists so the next test cycle can diff against it.
enum GraphLayoutTestsGoldenFixture {
    /// Fixture DAG commits in topo order (newest first).
    static func commits() -> [Commit] {
        // Deterministic timestamps descending by 1 hour per commit so any
        // Codable round-trip of the fixture is bitwise-stable.
        let base: TimeInterval = 1_700_000_000
        func make(_ sha: String, _ parents: [String], _ offset: Int, _ subject: String) -> Commit {
            Commit(
                sha: sha,
                parents: parents,
                authorName: "Fixture",
                authorEmail: "fixture@kite.local",
                authoredAt: Date(timeIntervalSince1970: base - Double(offset) * 3600),
                subject: subject
            )
        }

        return [
            make("M", ["F", "E"], 0, "merge feature back into main"),
            make("F", ["D"], 1, "main: tidy"),
            make("O", ["F", "D", "C"], 2, "octopus subtree merge"),
            make("X", ["Y"], 3, "orphan: rename module"),
            make("Y", ["Z"], 4, "orphan: split helpers"),
            make("Z", [], 5, "orphan root"),
            make("E", ["D", "C"], 6, "merge feature-x into main"),
            make("D", ["B"], 7, "main: bump version"),
            make("C", ["B"], 8, "feature-x: wire provider"),
            make("B", ["A"], 9, "main: add README"),
            make("A", [], 10, "main root"),
            make("P", [], 11, "unrelated root")
        ]
    }

    /// Path to the committed reference JSON, resolved from this source
    /// file's own location via `#filePath`. Living-alongside-tests means the
    /// fixture is always checked in, diffable in PRs, and loadable from any
    /// test run without special bundle-resource wiring.
    static func fixtureURL(filePath: StaticString = #filePath) -> URL {
        let sourceFile = URL(fileURLWithPath: String(describing: filePath))
        return sourceFile
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("goldenFixture.json")
    }

    /// Load the committed golden reference. If the file does not exist we
    /// write a fresh copy from the current algorithm output and return THAT
    /// — the equivalent of swift-snapshot-testing's "record mode". The next
    /// test run will read the committed JSON and diff against the live
    /// output, catching any algorithmic drift.
    static func loadReference(filePath: StaticString = #filePath) throws -> [LayoutRow] {
        let url = fixtureURL(filePath: filePath)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            return try decoder.decode([LayoutRow].self, from: data)
        }

        // Record mode: materialize the current output so the next test run
        // can diff against it. This path only runs once after a deliberate
        // delete-and-rerun; a clean CI build will never hit it.
        let rows = GraphLayout.compute(commits())
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(rows).write(to: url)
        return rows
    }
}
