import AppKit
import Foundation
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Kite

/// Snapshot coverage for the presentational `CommitHeaderView` + a combined
/// header-plus-diff view (VAL-DIFF-003 commit diff rendering, plus VAL-UI-010
/// dark-mode parity).
///
/// Each case is designed to produce a distinct md5 against every other
/// (AGENTS.md "Established patterns") — verified with
/// `md5 ... | sort -u | wc -l` after recording. A false green (byte-identical
/// bytes across cases) is considered a test failure, not a pass.
///
/// Per AGENTS.md:
///   - `NSHostingController.view.appearance` is set explicitly so dark/light
///     parity tests actually reflect `NSColor`-backed backgrounds.
///   - Content is wrapped in a `Color(nsColor: .windowBackgroundColor)`
///     background so the appearance swap renders distinct bytes across modes.
///   - We snapshot the presentational views directly — no environment, no
///     fixtures, no git.
///
/// Snapshot of `CommitDiffView` itself is intentionally skipped: it requires
/// `RepoStore` + async loading and is hard to drive meaningfully in-process;
/// its sub-views (`CommitHeaderView`, `FileDiffView`) are already covered
/// here and in `UncommittedDiffSnapshotTests`. `DiffPaneRouter` likewise
/// requires environment injection — handoff notes the skip.
final class CommitDiffSnapshotTests: XCTestCase {
    private static let width: CGFloat = 560

    // MARK: - Fixed-date helpers

    /// Fixed timestamp so snapshots don't drift with wall clock. UTC
    /// 2024-01-15 10:30 — keeps date-part stable across hosts given locale
    /// settings. `LC_ALL=C` in the test env keeps the month + AM/PM tokens
    /// deterministic; Kite fixtures already ride on that.
    private static let fixedDate = Date(timeIntervalSince1970: 1_705_318_200)

    private static func header(
        subject: String = "diff: add commit header rendering",
        body: String = "",
        refs: [RefKind] = []
    ) -> CommitHeader {
        CommitHeader(
            sha: "1234567890abcdef1234567890abcdef12345678",
            shortSHA: "1234567",
            authorName: "Kite Tests",
            authorEmail: "tests@kite.local",
            authoredAt: fixedDate,
            subject: subject,
            body: body,
            refs: refs
        )
    }

    private static func sampleFile() -> FileDiff {
        FileDiff(
            oldPath: "src/feature.swift",
            newPath: "src/feature.swift",
            isBinary: false,
            hunks: [
                Hunk(
                    oldStart: 12, oldCount: 2, newStart: 12, newCount: 4,
                    lines: [
                        .context("func feature() {"),
                        .added("    print(\"hello\")"),
                        .added("    print(\"world\")"),
                        .context("}")
                    ]
                )
            ]
        )
    }

    // MARK: - Case: header only, no body, no refs

    @MainActor
    func testHeaderOnly() {
        let host = Self.host(
            Self.wrap(CommitHeaderView(header: Self.header())),
            height: 120,
            appearance: .light
        )
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: Self.width, height: 120)),
            named: "CommitDiff.HeaderOnly.light"
        )
    }

    // MARK: - Case: header with multi-line body

    @MainActor
    func testHeaderWithBody() {
        let header = Self.header(
            subject: "diff: add commit header rendering",
            body: """
            First paragraph of the commit body.
            Second line with additional context.
            Third line explaining the rationale.
            """
        )
        let host = Self.host(
            Self.wrap(CommitHeaderView(header: header)),
            height: 180,
            appearance: .light
        )
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: Self.width, height: 180)),
            named: "CommitDiff.HeaderWithBody.light"
        )
    }

    // MARK: - Case: header with refs (local + remote branches)

    @MainActor
    func testHeaderWithRefs() {
        let header = Self.header(
            refs: [
                .localBranch("main"),
                .remoteBranch(remote: "origin", branch: "main")
            ]
        )
        let host = Self.host(
            Self.wrap(CommitHeaderView(header: header)),
            height: 150,
            appearance: .light
        )
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: Self.width, height: 150)),
            named: "CommitDiff.HeaderWithRefs.light"
        )
    }

    // MARK: - Case: full diff view (header + one file)

    @MainActor
    func testFullDiffView() {
        let view = VStack(alignment: .leading, spacing: 12) {
            CommitHeaderView(header: Self.header(
                subject: "feature: add greeting",
                body: "Introduces a two-line greeting call."
            ))
            FileDiffView(diff: Self.sampleFile())
        }
        let host = Self.host(Self.wrap(view), height: 340, appearance: .light)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: Self.width, height: 340)),
            named: "CommitDiff.FullDiffView.light"
        )
    }

    // MARK: - Case: dark-mode parity for the full diff view

    @MainActor
    func testDarkMode() {
        let view = VStack(alignment: .leading, spacing: 12) {
            CommitHeaderView(header: Self.header(
                subject: "feature: add greeting",
                body: "Introduces a two-line greeting call."
            ))
            FileDiffView(diff: Self.sampleFile())
        }
        let host = Self.host(Self.wrap(view), height: 340, appearance: .dark)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: Self.width, height: 340)),
            named: "CommitDiff.FullDiffView.dark"
        )
    }

    // MARK: - Helpers

    @MainActor
    private static func wrap(_ view: some View) -> some View {
        view
            .frame(width: width)
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
    }

    enum HostAppearance {
        case light
        case dark

        var appearance: NSAppearance {
            switch self {
            case .light:
                // swiftlint:disable:next force_unwrapping
                NSAppearance(named: .aqua)!
            case .dark:
                // swiftlint:disable:next force_unwrapping
                NSAppearance(named: .darkAqua)!
            }
        }
    }

    @MainActor
    private static func host<V: View>(
        _ view: V,
        height: CGFloat,
        appearance: HostAppearance
    ) -> NSHostingController<V> {
        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: Self.width, height: height)
        host.view.appearance = appearance.appearance
        return host
    }
}
