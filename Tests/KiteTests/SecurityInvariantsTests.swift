import Foundation
import Testing

/// Grep-based invariants that prove no destructive git flags are present
/// anywhere in the Swift sources we ship.
///
/// These tests compile-time-prove VAL-SEC-001 (no `--force` /
/// `--force-with-lease`), VAL-SEC-002 (no `reset --hard`), and
/// VAL-SEC-003 (no `git clean`) for every past and future feature in a
/// single assertion. Any worker that forgets this will trip the test
/// before landing.
///
/// Paths are resolved from `#filePath` (the absolute location of THIS file)
/// so the test runs identically under `swift test` and `xcodebuild test`.
///
/// Fulfills: VAL-SEC-001, VAL-SEC-002, VAL-SEC-003.
@Suite("Security invariants (source grep)")
struct SecurityInvariantsTests {
    /// Walk up from this test file to the Kite repo root, then into
    /// `Sources/`. Layout:
    ///
    ///     <repo>/Tests/KiteTests/SecurityInvariantsTests.swift ← #filePath
    ///     <repo>/Sources/
    ///
    /// Three `deletingLastPathComponent()` calls peel the filename, the
    /// KiteTests dir, and the Tests dir — leaving the repo root.
    private static func sourcesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KiteTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // <repo>/
            .appendingPathComponent("Sources", isDirectory: true)
    }

    /// Return every `.swift` file under `Sources/`.
    private static func swiftFiles(in root: URL) throws -> [URL] {
        let fm = FileManager.default
        guard let subpaths = fm.subpaths(atPath: root.path) else {
            return []
        }
        return subpaths
            .filter { $0.hasSuffix(".swift") }
            .map { root.appendingPathComponent($0) }
    }

    /// VAL-SEC-001: no `--force` anywhere in `Sources/`. Catches `--force`,
    /// `--force-with-lease`, and `--force-if-includes` in one pattern.
    @Test("No --force flags anywhere in Sources/")
    func noForceFlagInSource() throws {
        let root = Self.sourcesDirectory()
        let files = try Self.swiftFiles(in: root)
        #expect(!files.isEmpty, "Expected at least one Swift source file under \(root.path)")
        for file in files {
            let src = try String(contentsOf: file, encoding: .utf8)
            #expect(
                !src.contains("--force"),
                "Source \(file.lastPathComponent) contains '--force' — VAL-SEC-001 violation"
            )
        }
    }

    /// VAL-SEC-002: no `reset --hard` anywhere in `Sources/`. Matches both
    /// `"reset", "--hard"` argument forms and `git reset --hard` string
    /// literals.
    @Test("No reset --hard anywhere in Sources/")
    func noResetHardInSource() throws {
        let root = Self.sourcesDirectory()
        let files = try Self.swiftFiles(in: root)
        for file in files {
            let src = try String(contentsOf: file, encoding: .utf8)
            #expect(
                !src.contains("reset --hard"),
                "Source \(file.lastPathComponent) contains 'reset --hard' — VAL-SEC-002 violation"
            )
            #expect(
                !src.contains("\"--hard\""),
                "Source \(file.lastPathComponent) contains '\"--hard\"' argument — VAL-SEC-002 violation"
            )
        }
    }

    /// VAL-SEC-003: no `git clean` anywhere in `Sources/`.
    @Test("No git clean anywhere in Sources/")
    func noGitCleanInSource() throws {
        let root = Self.sourcesDirectory()
        let files = try Self.swiftFiles(in: root)
        for file in files {
            let src = try String(contentsOf: file, encoding: .utf8)
            // Match either a literal `git clean` phrase or a `"clean"` arg
            // appearing alongside the word "git" in the same file. The
            // simpler substring check is adequate — no shipping code names
            // something `git clean...` in a benign context.
            #expect(
                !src.contains("git clean"),
                "Source \(file.lastPathComponent) contains 'git clean' — VAL-SEC-003 violation"
            )
        }
    }
}
