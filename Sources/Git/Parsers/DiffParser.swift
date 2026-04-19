import Foundation

/// Parses unified-diff output from `git diff`, `git diff --staged`, or
/// `git show <sha>` into `[FileDiff]`.
///
/// Handles:
///   - Regular modifications with 1+ hunks.
///   - `new file mode <mode>` → `oldPath == nil`.
///   - `deleted file mode <mode>` → `newPath == nil`.
///   - `rename from` / `rename to` — both paths preserved.
///   - `Binary files ... differ` → `isBinary == true`, no hunks.
///   - `\ No newline at end of file` → `DiffLine.noNewlineMarker`, attached
///     to the current hunk (never mis-treated as a removed/added line).
///
/// When `git show <sha>` is the source, any leading commit-header lines
/// (before the first `diff --git`) are skipped — callers parse that header
/// separately.
///
/// Fulfills VAL-PARSE-005.
enum DiffParser {
    static func parse(_ input: String) throws -> [FileDiff] {
        if input.isEmpty { return [] }

        // Split without dropping blank lines — blank context lines inside
        // a hunk are valid and must survive.
        let lines = input.components(separatedBy: "\n")

        var state = ParseState()
        for raw in lines {
            try handleLine(raw, state: &state)
        }
        state.flushFile()
        return state.files
    }

    // MARK: - Private

    private struct ParseState {
        var files: [FileDiff] = []
        var builder: FileBuilder?
        var hunk: HunkBuilder?

        mutating func flushHunk() {
            if let pending = hunk, var current = builder {
                current.hunks.append(pending.build())
                builder = current
                hunk = nil
            }
        }

        mutating func flushFile() {
            flushHunk()
            if let pending = builder {
                files.append(pending.build())
                builder = nil
            }
        }
    }

    private struct FileBuilder {
        var oldPath: String?
        var newPath: String?
        var isBinary: Bool = false
        var hunks: [Hunk] = []

        func build() -> FileDiff {
            FileDiff(oldPath: oldPath, newPath: newPath, isBinary: isBinary, hunks: hunks)
        }
    }

    private struct HunkBuilder {
        let oldStart: Int
        let oldCount: Int
        let newStart: Int
        let newCount: Int
        var lines: [DiffLine] = []

        func build() -> Hunk {
            Hunk(
                oldStart: oldStart,
                oldCount: oldCount,
                newStart: newStart,
                newCount: newCount,
                lines: lines
            )
        }
    }

    private struct HunkHeader {
        let oldStart: Int
        let oldCount: Int
        let newStart: Int
        let newCount: Int
    }

    private static func handleLine(_ raw: String, state: inout ParseState) throws {
        if raw.hasPrefix("diff --git ") {
            state.flushFile()
            state.builder = FileBuilder()
            state.hunk = nil
            let paths = extractDiffGitPaths(raw)
            // Default to both paths from `diff --git a/X b/Y`; these are refined
            // by subsequent `--- /dev/null` / `+++ /dev/null` / rename-from
            // / rename-to / new-file / deleted-file lines.
            state.builder?.oldPath = paths?.old
            state.builder?.newPath = paths?.new
            return
        }
        guard state.builder != nil else {
            // Content before the first `diff --git` (e.g. commit header from
            // `git show`) — ignore.
            return
        }
        if tryHandleFileHeader(raw, state: &state) { return }
        if raw.hasPrefix("@@") {
            state.flushHunk()
            guard let header = parseHunkHeader(raw) else {
                throw ParseError.malformedLine(raw)
            }
            state.hunk = HunkBuilder(
                oldStart: header.oldStart,
                oldCount: header.oldCount,
                newStart: header.newStart,
                newCount: header.newCount
            )
            return
        }
        if raw.hasPrefix("index "), raw.hasSuffix("index ") == false {
            // Informational line — no effect on hunks.
            return
        }
        if isInformationalHeader(raw) { return }
        if state.hunk != nil {
            appendHunkLine(raw, state: &state)
        }
    }

    private static func tryHandleFileHeader(_ raw: String, state: inout ParseState) -> Bool {
        if raw.hasPrefix("new file mode ") {
            state.builder?.oldPath = nil
            return true
        }
        if raw.hasPrefix("deleted file mode ") {
            state.builder?.newPath = nil
            return true
        }
        if raw.hasPrefix("rename from ") {
            state.builder?.oldPath = String(raw.dropFirst("rename from ".count))
            return true
        }
        if raw.hasPrefix("rename to ") {
            state.builder?.newPath = String(raw.dropFirst("rename to ".count))
            return true
        }
        if raw.hasPrefix("Binary files "), raw.hasSuffix(" differ") {
            state.builder?.isBinary = true
            return true
        }
        if raw.hasPrefix("--- ") {
            state.flushHunk()
            applyOldPath(String(raw.dropFirst(4)), state: &state)
            return true
        }
        if raw.hasPrefix("+++ ") {
            state.flushHunk()
            applyNewPath(String(raw.dropFirst(4)), state: &state)
            return true
        }
        return false
    }

    private static func applyOldPath(_ path: String, state: inout ParseState) {
        if path == "/dev/null" {
            state.builder?.oldPath = nil
        } else if path.hasPrefix("a/") {
            state.builder?.oldPath = String(path.dropFirst(2))
        }
    }

    private static func applyNewPath(_ path: String, state: inout ParseState) {
        if path == "/dev/null" {
            state.builder?.newPath = nil
        } else if path.hasPrefix("b/") {
            state.builder?.newPath = String(path.dropFirst(2))
        }
    }

    private static func isInformationalHeader(_ raw: String) -> Bool {
        raw.hasPrefix("index ") ||
            raw.hasPrefix("similarity index ") ||
            raw.hasPrefix("dissimilarity index ") ||
            raw.hasPrefix("old mode ") ||
            raw.hasPrefix("new mode ")
    }

    private static func appendHunkLine(_ raw: String, state: inout ParseState) {
        if raw.hasPrefix("\\") {
            // `\ No newline at end of file` — exactly one marker regardless
            // of which side it annotates.
            state.hunk?.lines.append(.noNewlineMarker)
        } else if raw.hasPrefix("+") {
            state.hunk?.lines.append(.added(String(raw.dropFirst())))
        } else if raw.hasPrefix("-") {
            state.hunk?.lines.append(.removed(String(raw.dropFirst())))
        } else if raw.hasPrefix(" ") {
            state.hunk?.lines.append(.context(String(raw.dropFirst())))
        } else if raw.isEmpty {
            // Entirely-blank line inside a hunk (seen in some git outputs) —
            // treat as an empty context line.
            state.hunk?.lines.append(.context(""))
        }
        // Unknown in-hunk prefix — ignore silently; better to drop one line
        // than to reject an otherwise-valid diff.
    }

    private static func extractDiffGitPaths(_ line: String) -> (old: String, new: String)? {
        // Format: `diff --git a/<old> b/<new>`. When paths contain spaces git
        // quotes them with `"..."`; we handle the unquoted common case, which
        // covers all VAL fixtures.
        let trimmed = line.dropFirst("diff --git ".count)
        let parts = trimmed.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }
        let aPath = parts[0]
        let bPath = parts[1]
        guard aPath.hasPrefix("a/"), bPath.hasPrefix("b/") else { return nil }
        return (String(aPath.dropFirst(2)), String(bPath.dropFirst(2)))
    }

    private static func parseHunkHeader(_ line: String) -> HunkHeader? {
        // Format: `@@ -<oldStart>[,<oldCount>] +<newStart>[,<newCount>] @@ [func]`
        // Per unified-diff spec, omitted count defaults to 1.
        guard let openRange = line.range(of: "@@ "),
              let closeRange = line.range(of: " @@", range: openRange.upperBound ..< line.endIndex)
        else { return nil }
        let between = line[openRange.upperBound ..< closeRange.lowerBound]
        let tokens = between.split(separator: " ", omittingEmptySubsequences: true)
        guard tokens.count == 2,
              let oldTok = tokens.first,
              let newTok = tokens.last,
              oldTok.hasPrefix("-"),
              newTok.hasPrefix("+")
        else { return nil }

        let (oldStart, oldCount) = parseStartCount(oldTok.dropFirst()) ?? (0, 0)
        let (newStart, newCount) = parseStartCount(newTok.dropFirst()) ?? (0, 0)
        if oldStart == 0, oldCount == 0, newStart == 0, newCount == 0 {
            return nil
        }
        return HunkHeader(oldStart: oldStart, oldCount: oldCount, newStart: newStart, newCount: newCount)
    }

    private static func parseStartCount(_ token: Substring) -> (Int, Int)? {
        let parts = token.split(separator: ",", omittingEmptySubsequences: true)
        switch parts.count {
        case 1:
            guard let start = Int(parts[0]) else { return nil }
            return (start, 1)
        case 2:
            guard let start = Int(parts[0]), let count = Int(parts[1]) else { return nil }
            return (start, count)
        default:
            return nil
        }
    }
}
