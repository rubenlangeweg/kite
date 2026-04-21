import AppKit
import Foundation
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Kite

/// Snapshot coverage for the presentational `FileDiffView` across every
/// visual branch we care about (VAL-DIFF-001/004/005 + VAL-UI-010 dark mode).
///
/// Each case is designed to produce a distinct md5 against every other
/// (AGENTS.md "Established patterns") — verified with
/// `md5 ... | sort -u | wc -l` after recording. A false green (byte-identical
/// bytes across cases) is considered a test failure, not a pass.
///
/// Per AGENTS.md:
///   - `NSHostingController.view.appearance` is set explicitly so dark/light
///     parity tests actually reflect `NSColor.controlBackgroundColor` —
///     `.preferredColorScheme` alone doesn't propagate to `NSColor`-backed
///     backgrounds.
///   - Content is wrapped in a `Color(nsColor: .windowBackgroundColor)`
///     background so the appearance swap renders distinct bytes across modes.
///   - We snapshot the inner `FileDiffView` directly — no environment, no
///     fixtures, no git.
final class UncommittedDiffSnapshotTests: XCTestCase {
    private static let width: CGFloat = 520

    // MARK: - Case: simple file with three added lines

    @MainActor
    func testSimpleAddedLines() {
        let diff = FileDiff(
            oldPath: "app/config.yml",
            newPath: "app/config.yml",
            isBinary: false,
            hunks: [
                Hunk(
                    oldStart: 1, oldCount: 1, newStart: 1, newCount: 4,
                    lines: [
                        .context("name: kite"),
                        .added("version: 0.1.0"),
                        .added("platform: macos"),
                        .added("swiftVersion: 5.9")
                    ]
                )
            ]
        )
        let host = Self.host(Self.wrap(diff: diff), height: 160, appearance: .light)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: Self.width, height: 160)),
            named: "UncommittedDiff.SimpleAddedLines.light"
        )
    }

    // MARK: - Case: mixed adds + removes

    @MainActor
    func testMixedAddRemove() {
        let host = Self.host(Self.wrap(diff: Self.mixedAddRemoveDiff()), height: 200, appearance: .light)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: Self.width, height: 200)),
            named: "UncommittedDiff.MixedAddRemove.light"
        )
    }

    // MARK: - Case: binary file placeholder

    @MainActor
    func testBinaryFile() {
        let diff = FileDiff(
            oldPath: "Resources/logo.png",
            newPath: "Resources/logo.png",
            isBinary: true,
            hunks: []
        )
        let host = Self.host(Self.wrap(diff: diff), height: 100, appearance: .light)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: Self.width, height: 100)),
            named: "UncommittedDiff.Binary.light"
        )
    }

    // MARK: - Case: multiple hunks

    @MainActor
    func testMultipleHunks() {
        let diff = FileDiff(
            oldPath: "src/core.swift",
            newPath: "src/core.swift",
            isBinary: false,
            hunks: [
                Hunk(
                    oldStart: 10, oldCount: 2, newStart: 10, newCount: 3,
                    lines: [
                        .context("func alpha() {"),
                        .added("    print(\"alpha\")"),
                        .context("}")
                    ]
                ),
                Hunk(
                    oldStart: 42, oldCount: 3, newStart: 43, newCount: 2,
                    lines: [
                        .context("func beta() {"),
                        .removed("    print(\"beta\")"),
                        .removed("    // TODO"),
                        .added("    print(\"beta-v2\")"),
                        .context("}")
                    ]
                )
            ]
        )
        let host = Self.host(Self.wrap(diff: diff), height: 280, appearance: .light)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: Self.width, height: 280)),
            named: "UncommittedDiff.MultipleHunks.light"
        )
    }

    // MARK: - Case: no-newline-at-EOF marker

    @MainActor
    func testNoNewlineAtEOF() {
        let diff = FileDiff(
            oldPath: "script.sh",
            newPath: "script.sh",
            isBinary: false,
            hunks: [
                Hunk(
                    oldStart: 1, oldCount: 2, newStart: 1, newCount: 2,
                    lines: [
                        .context("#!/bin/sh"),
                        .removed("echo old"),
                        .added("echo new"),
                        .noNewlineMarker
                    ]
                )
            ]
        )
        let host = Self.host(Self.wrap(diff: diff), height: 160, appearance: .light)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: Self.width, height: 160)),
            named: "UncommittedDiff.NoNewlineAtEOF.light"
        )
    }

    // MARK: - Dark mode parity

    @MainActor
    func testDarkMode() {
        let host = Self.host(Self.wrap(diff: Self.mixedAddRemoveDiff()), height: 200, appearance: .dark)
        assertSnapshot(
            of: host,
            as: .image(size: CGSize(width: Self.width, height: 200)),
            named: "UncommittedDiff.MixedAddRemove.dark"
        )
    }

    // MARK: - Shared fixture

    @MainActor
    private static func mixedAddRemoveDiff() -> FileDiff {
        FileDiff(
            oldPath: "README.md",
            newPath: "README.md",
            isBinary: false,
            hunks: [
                Hunk(
                    oldStart: 1, oldCount: 3, newStart: 1, newCount: 4,
                    lines: [
                        .context("# Project"),
                        .removed("legacy intro"),
                        .added("modern intro"),
                        .added("second added line"),
                        .context("")
                    ]
                )
            ]
        )
    }

    // MARK: - Helpers

    @MainActor
    private static func wrap(diff: FileDiff) -> some View {
        FileDiffView(diff: diff)
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
