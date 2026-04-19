import Foundation

/// A single file's diff parsed from unified `git diff` / `git show` output.
/// `oldPath` is nil for newly-added files; `newPath` is nil for deletions.
/// Binary files carry `isBinary == true` and no hunks (git emits only a
/// `Binary files ... differ` marker).
struct FileDiff: Equatable {
    let oldPath: String?
    let newPath: String?
    let isBinary: Bool
    let hunks: [Hunk]
}

/// A single hunk within a file diff. Line numbers match git's 1-based
/// convention. `oldCount`/`newCount` are the sizes git reports in the
/// `@@ -<oldStart>,<oldCount> +<newStart>,<newCount> @@` header; when git
/// omits the count (single-line hunks) we substitute 1 per the unified-diff
/// spec.
struct Hunk: Equatable {
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let lines: [DiffLine]
}

/// A single line within a hunk. `noNewlineMarker` captures the
/// `\ No newline at end of file` sentinel git emits after the last line of
/// a file without a trailing newline.
enum DiffLine: Equatable {
    case context(String)
    case added(String)
    case removed(String)
    case noNewlineMarker
}
