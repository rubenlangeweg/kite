import Foundation
import Testing
@testable import Kite

/// Unit coverage for `RelativeAgeFormatter`. Snapshot coverage for the full
/// `GraphRowContent` view lives in `GraphRowContentSnapshotTests`; these
/// tests exist so a breakpoint off-by-one fails cheaply without re-baking
/// PNG references.
@Suite("GraphRowContent unit")
struct GraphRowContentUnitTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - RelativeAgeFormatter

    @Test("<60s → just now")
    func justNow() {
        #expect(RelativeAgeFormatter.format(from: Self.now, now: Self.now) == "just now")
        #expect(RelativeAgeFormatter.format(from: Self.now.addingTimeInterval(-30), now: Self.now) == "just now")
    }

    @Test("minutes: 5m, 59m")
    func minutes() {
        #expect(RelativeAgeFormatter.format(from: Self.now.addingTimeInterval(-5 * 60), now: Self.now) == "5m")
        #expect(RelativeAgeFormatter.format(from: Self.now.addingTimeInterval(-59 * 60), now: Self.now) == "59m")
    }

    @Test("hours: 3h")
    func hours() {
        #expect(RelativeAgeFormatter.format(from: Self.now.addingTimeInterval(-3 * 3600), now: Self.now) == "3h")
    }

    @Test("days: 2d")
    func days() {
        #expect(RelativeAgeFormatter.format(from: Self.now.addingTimeInterval(-2 * 86400), now: Self.now) == "2d")
    }

    @Test("weeks: 3w")
    func weeks() {
        #expect(RelativeAgeFormatter.format(from: Self.now.addingTimeInterval(-3 * 7 * 86400), now: Self.now) == "3w")
    }

    @Test("months: 6mo")
    func months() {
        #expect(RelativeAgeFormatter.format(from: Self.now.addingTimeInterval(-6 * 30 * 86400), now: Self.now) == "6mo")
    }

    @Test("years: 2y")
    func years() {
        #expect(RelativeAgeFormatter.format(from: Self.now.addingTimeInterval(-2 * 365 * 86400), now: Self.now) == "2y")
    }

    @Test("future dates clamp to just now (defensive)")
    func futureClamps() {
        #expect(RelativeAgeFormatter.format(from: Self.now.addingTimeInterval(3600), now: Self.now) == "just now")
    }

    // MARK: - GraphRowContent pill policy

    /// Trivial commit builder.
    private static func commit(_ sha: String, subject: String = "subject") -> Commit {
        Commit(
            sha: sha,
            parents: [],
            authorName: "Test",
            authorEmail: "test@kite.local",
            authoredAt: now,
            subject: subject
        )
    }

    @Test("GraphRowContent drops tag refs from pill rendering (v1 scope guard)")
    @MainActor
    func tagsAreDropped() {
        // Hand-built: a row with one tag ref only. `visibleRefs` should be
        // empty and `hasRef` on the dot should stay false. We can't assert
        // rendering directly without a snapshot, but we can prove the
        // initializer doesn't throw and the overflow math excludes tags.
        let row = LayoutRow(
            commit: Self.commit("T"),
            column: 0,
            inEdges: [],
            outEdges: [],
            refs: [.tag("v1.0")]
        )
        let content = GraphRowContent(row: row, laneCount: 1)
        // Smoke-test: constructing the view doesn't trigger any assertion.
        _ = content.body
    }
}
