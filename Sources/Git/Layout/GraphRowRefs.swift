import Foundation

/// Post-layout enrichment: attaches branch refs to `[LayoutRow]` using the
/// `[sha: [RefKind]]` map produced by `ForEachRefParser`.
///
/// `GraphLayout.compute` intentionally leaves `LayoutRow.refs` empty (library
/// §6 — the layout algorithm is a pure function of topology, not refs). This
/// enum is the adapter that joins the two data sources just before rendering.
///
/// Scope per M4-graph-row-meta — v1 is branches-only:
///   - `.localBranch` and `.remoteBranch` pass through.
///   - `.tag` entries are dropped (deferred to v2 per mission §3 "Out of scope").
///   - If `currentBranch` matches a `.localBranch` on a given commit, a
///     synthetic `.head` ref is PREPENDED so the pill row reads
///     `HEAD → <branch> origin/branch …`.
///   - Detached-HEAD detection is NOT this function's job; the status header
///     surfaces that case (VAL-BRANCH-004).
///
/// Pure function over in-memory inputs so tests don't need a fixture repo.
enum GraphRowRefs {
    /// Attach refs to layout rows.
    /// - Parameters:
    ///   - rows: `[LayoutRow]` from `GraphLayout.compute`.
    ///   - refsBySHA: commit-SHA → `[RefKind]` map from `ForEachRefParser`.
    ///   - currentBranch: short name of the checked-out branch (e.g. `"main"`)
    ///     or `nil` when HEAD is detached / unknown.
    /// - Returns: a parallel `[LayoutRow]` with `refs` populated (branches only).
    static func enrich(
        _ rows: [LayoutRow],
        refsBySHA: [String: [RefKind]],
        currentBranch: String?
    ) -> [LayoutRow] {
        if refsBySHA.isEmpty { return rows }

        return rows.map { row in
            let rawRefs = refsBySHA[row.commit.sha] ?? []
            let filtered = rawRefs.filter { !isTag($0) }
            if filtered.isEmpty { return row }

            let finalRefs = prependHeadIfCurrent(filtered, currentBranch: currentBranch)
            return LayoutRow(
                commit: row.commit,
                column: row.column,
                inEdges: row.inEdges,
                outEdges: row.outEdges,
                refs: finalRefs
            )
        }
    }

    // MARK: - Private

    private static func isTag(_ ref: RefKind) -> Bool {
        if case .tag = ref { return true }
        return false
    }

    /// Prepend a synthetic `.head` marker when a `.localBranch` in `refs`
    /// matches the currently checked-out branch — this is how the pill row
    /// renders the canonical `HEAD → main` marker.
    private static func prependHeadIfCurrent(_ refs: [RefKind], currentBranch: String?) -> [RefKind] {
        guard let currentBranch else { return refs }
        let hasMatchingLocal = refs.contains { ref in
            if case let .localBranch(name) = ref { return name == currentBranch }
            return false
        }
        guard hasMatchingLocal else { return refs }
        return [.head] + refs
    }
}
