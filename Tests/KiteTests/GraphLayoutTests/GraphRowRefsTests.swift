import Foundation
import Testing
@testable import Kite

/// Unit coverage for the post-layout `GraphRowRefs.enrich` adapter.
///
/// The enrichment step is pure and non-trivial — it filters tags, prepends a
/// synthetic `.head` entry, and preserves edges / column assignments
/// unchanged. These tests pin each behaviour so the scroll container (M4-graph-
/// scroll-container) can trust the input shape.
@Suite("GraphRowRefs.enrich")
struct GraphRowRefsTests {
    // MARK: - Commit / row builders

    private static func commit(_ sha: String) -> Commit {
        Commit(
            sha: sha,
            parents: [],
            authorName: "Test",
            authorEmail: "test@kite.local",
            authoredAt: Date(timeIntervalSince1970: 1_700_000_000),
            subject: "commit \(sha)"
        )
    }

    private static func row(_ sha: String, column: Int = 0) -> LayoutRow {
        LayoutRow(
            commit: commit(sha),
            column: column,
            inEdges: [],
            outEdges: [],
            refs: []
        )
    }

    // MARK: - 1. Populates local branches for matching SHAs

    @Test("enrich populates local-branch refs for matching SHAs")
    func enrichPopulatesLocalBranches() {
        let rows = [Self.row("A"), Self.row("B"), Self.row("C")]
        let refs: [String: [RefKind]] = [
            "A": [.localBranch("feature-x")],
            "C": [.localBranch("main")]
        ]

        let enriched = GraphRowRefs.enrich(rows, refsBySHA: refs, currentBranch: nil)

        #expect(enriched.count == 3)
        #expect(enriched[0].refs == [.localBranch("feature-x")])
        #expect(enriched[1].refs.isEmpty, "B has no ref in the map and must stay empty")
        #expect(enriched[2].refs == [.localBranch("main")])
    }

    // MARK: - 2. Tags are dropped

    @Test("enrich drops tag refs (v1 scope — branches only)")
    func enrichSkipsTags() {
        let rows = [Self.row("A")]
        let refs: [String: [RefKind]] = [
            "A": [
                .localBranch("main"),
                .tag("v1.0"),
                .remoteBranch(remote: "origin", branch: "main"),
                .tag("release-1.0")
            ]
        ]

        let enriched = GraphRowRefs.enrich(rows, refsBySHA: refs, currentBranch: nil)

        #expect(enriched.count == 1)
        let got = enriched[0].refs
        #expect(got.contains(.localBranch("main")))
        #expect(got.contains(.remoteBranch(remote: "origin", branch: "main")))
        // None of the returned refs should be a tag.
        for ref in got {
            if case .tag = ref {
                Issue.record("tag ref leaked into enriched output: \(ref)")
            }
        }
    }

    // MARK: - 3. HEAD is prepended when currentBranch matches

    @Test("enrich prepends .head when currentBranch matches a localBranch on that commit")
    func enrichPrependsHEADForCurrentBranch() {
        let rows = [Self.row("A")]
        let refs: [String: [RefKind]] = [
            "A": [.localBranch("main"), .remoteBranch(remote: "origin", branch: "main")]
        ]

        let enriched = GraphRowRefs.enrich(rows, refsBySHA: refs, currentBranch: "main")

        #expect(enriched[0].refs.first == .head, "HEAD pill must come first so it reads 'HEAD → main'")
        #expect(enriched[0].refs.contains(.localBranch("main")))
    }

    @Test("enrich does NOT prepend .head when currentBranch doesn't match any localBranch on the commit")
    func enrichDoesNotPrependHEADWhenNoMatch() {
        let rows = [Self.row("A")]
        let refs: [String: [RefKind]] = [
            "A": [.localBranch("feature-x")]
        ]

        let enriched = GraphRowRefs.enrich(rows, refsBySHA: refs, currentBranch: "main")

        // currentBranch is main but A carries only feature-x — no HEAD pill.
        #expect(enriched[0].refs == [.localBranch("feature-x")])
    }

    @Test("enrich does NOT prepend .head when currentBranch is nil (detached)")
    func enrichDoesNotPrependHEADWhenDetached() {
        let rows = [Self.row("A")]
        let refs: [String: [RefKind]] = [
            "A": [.localBranch("main")]
        ]

        let enriched = GraphRowRefs.enrich(rows, refsBySHA: refs, currentBranch: nil)

        #expect(
            enriched[0].refs == [.localBranch("main")],
            "no HEAD pill when HEAD is detached — that case is handled by the status header"
        )
    }

    // MARK: - 4. Empty refs map is a no-op

    @Test("enrich with empty refsBySHA returns rows unchanged")
    func enrichReturnsRowsUnchangedWhenNoRefs() {
        let rows = [Self.row("A"), Self.row("B", column: 1)]
        let enriched = GraphRowRefs.enrich(rows, refsBySHA: [:], currentBranch: "main")
        #expect(enriched == rows, "empty map short-circuits; rows returned as-is")
    }

    // MARK: - 5. Non-ref fields preserved

    @Test("enrich preserves column and edges on rows it modifies")
    func enrichPreservesOtherFields() {
        let edge = LaneEdge(fromColumn: 0, toColumn: 0, color: .blue)
        let original = LayoutRow(
            commit: Self.commit("A"),
            column: 3,
            inEdges: [edge],
            outEdges: [edge],
            refs: []
        )
        let refs: [String: [RefKind]] = ["A": [.localBranch("main")]]

        let enriched = GraphRowRefs.enrich([original], refsBySHA: refs, currentBranch: nil)
        #expect(enriched[0].column == 3)
        #expect(enriched[0].inEdges == [edge])
        #expect(enriched[0].outEdges == [edge])
        #expect(enriched[0].refs == [.localBranch("main")])
    }
}
