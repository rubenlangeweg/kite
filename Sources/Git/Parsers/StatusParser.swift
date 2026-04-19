import Foundation

/// Parses `git status --porcelain=v2 --branch -z` output into `StatusSummary`.
///
/// Records are `\0`-separated. Entry types:
///
///   - `# branch.oid <sha>`
///   - `# branch.head <name>` (name is `(detached)` when HEAD is detached)
///   - `# branch.upstream <ref>` (only when upstream is set)
///   - `# branch.ab +N -M` (only when upstream is set)
///   - `1 XY <submodule-state> <mh> <mi> <mw> <hH> <hI> <path>` — ordinary change
///   - `2 XY <submodule-state> <mh> <mi> <mw> <hH> <hI> <Rx><score> <path>`
///     followed by `<origPath>` as the next `\0`-separated record (rename/copy)
///   - `u XY <submodule-state> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>` — unmerged
///   - `? <path>` — untracked
///   - `! <path>` — ignored (only with `--ignored`, we don't pass)
///
/// `XY` is two status letters: X = index vs HEAD, Y = worktree vs index.
///
/// We count:
///   - `staged` = entries where X != `.`
///   - `modified` = entries where Y != `.`
///   - `untracked` = `?` entries
///
/// Unmerged entries count toward both staged and modified (they represent an
/// in-progress conflict touching both sides).
///
/// Fulfills VAL-PARSE-003.
enum StatusParser {
    private struct ParseState {
        var branch: String?
        var detachedAt: String?
        var upstream: String?
        var ahead = 0
        var behind = 0
        var staged = 0
        var modified = 0
        var untracked = 0

        func summary() -> StatusSummary {
            StatusSummary(
                branch: branch,
                detachedAt: detachedAt,
                upstream: upstream,
                ahead: ahead,
                behind: behind,
                staged: staged,
                modified: modified,
                untracked: untracked
            )
        }
    }

    static func parse(_ input: String) throws -> StatusSummary {
        var state = ParseState()

        // Split on NUL preserving empties so we can detect the rename-pair
        // trailing path even when surrounding fields are empty.
        let records = input.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)

        var index = 0
        while index < records.count {
            let record = records[index]
            index += 1
            if record.isEmpty { continue }
            index += try consume(record, state: &state)
        }

        return state.summary()
    }

    // MARK: - Private

    /// Parses a single record, mutating state. Returns the number of
    /// *additional* records consumed (for the rename/copy trailing path),
    /// so the caller can advance past them.
    private static func consume(_ record: String, state: inout ParseState) throws -> Int {
        if record.hasPrefix("# ") {
            try parseBranchHeader(record, state: &state)
            return 0
        }

        guard let kind = record.first else { return 0 }
        switch kind {
        case "1":
            try countOrdinary(record, staged: &state.staged, modified: &state.modified)
            return 0
        case "2":
            try countOrdinary(record, staged: &state.staged, modified: &state.modified)
            // Rename/copy entries are followed by the original path in the
            // next NUL-separated record. Its content doesn't affect counts
            // but we must skip it so later parsing stays aligned.
            return 1
        case "u":
            state.staged += 1
            state.modified += 1
            return 0
        case "?":
            state.untracked += 1
            return 0
        case "!", "#":
            return 0
        default:
            // Unknown record type — skip rather than throw; status v2 is
            // forward-compatible and we shouldn't break on new entry types.
            return 0
        }
    }

    private static func parseBranchHeader(
        _ record: String,
        state: inout ParseState
    ) throws {
        // Strip the leading "# " then split into key + value.
        let body = record.dropFirst(2)
        guard let spaceIdx = body.firstIndex(of: " ") else {
            // Header with no value — tolerate silently; git never emits this.
            return
        }
        let key = String(body[..<spaceIdx])
        let value = String(body[body.index(after: spaceIdx)...])

        switch key {
        case "branch.oid":
            // We don't surface the OID in StatusSummary, but do capture it
            // as the short-sha when detached (overwritten below if branch.head
            // is a real branch).
            if state.detachedAt == nil, state.branch == nil {
                state.detachedAt = String(value.prefix(7))
            }
        case "branch.head":
            if value == "(detached)" {
                state.branch = nil
                // detachedAt was set from branch.oid above; keep it.
            } else {
                state.branch = value
                state.detachedAt = nil
            }
        case "branch.upstream":
            state.upstream = value
        case "branch.ab":
            // Format: "+N -M"
            try parseAheadBehind(value, state: &state)
        default:
            // Unknown header — ignore (forward-compatible).
            break
        }
    }

    private static func parseAheadBehind(
        _ value: String,
        state: inout ParseState
    ) throws {
        let parts = value.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2,
              parts[0].hasPrefix("+"),
              parts[1].hasPrefix("-"),
              let aheadValue = Int(parts[0].dropFirst()),
              let behindValue = Int(parts[1].dropFirst())
        else {
            throw ParseError.invalidField(field: "branch.ab", value: value)
        }
        state.ahead = aheadValue
        state.behind = behindValue
    }

    private static func countOrdinary(
        _ record: String,
        staged: inout Int,
        modified: inout Int
    ) throws {
        // Format: "1 XY ..." — we only need the X and Y letters at offsets 2, 3.
        let chars = Array(record)
        guard chars.count >= 4, chars[1] == " " else {
            throw ParseError.malformedLine(record)
        }
        let indexSide = chars[2]
        let worktreeSide = chars[3]
        if indexSide != "." { staged += 1 }
        if worktreeSide != "." { modified += 1 }
    }
}
