import Foundation

/// Parses null-delimited output from `git branch --list --format=...` / `git branch -r --format=...`.
///
/// Expected format (6 NUL-separated fields, records separated by `\n`):
///
/// ```
/// %(refname:short)\x00%(refname)\x00%(objectname)\x00%(upstream:short)\x00%(upstream:track)\x00%(HEAD)
/// ```
///
/// - `upstream:track` is bracketed: `[ahead N]`, `[behind M]`, `[ahead N, behind M]`, `[gone]`, or empty.
/// - HEAD column is `*` for the currently-checked-out branch and `space` otherwise.
/// - Remote-tracking records carry `refs/remotes/<remote>/<branch>` as full refname.
///
/// Fulfills VAL-PARSE-001.
enum BranchParser {
    static func parse(_ input: String) throws -> [Branch] {
        if input.isEmpty { return [] }

        var branches: [Branch] = []
        for rawLine in input.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            if line.isEmpty { continue }

            // Fields are NUL-separated. Do not omit empty subsequences — we
            // rely on the positional layout and empty fields are meaningful
            // (e.g. no upstream).
            let fields = line.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 6 else {
                throw ParseError.malformedLine(line)
            }

            let shortName = fields[0]
            let fullName = fields[1]
            let sha = fields[2]
            let upstreamRaw = fields[3]
            let trackRaw = fields[4]
            let headMarker = fields[5]

            if shortName.isEmpty || fullName.isEmpty || sha.isEmpty {
                throw ParseError.malformedLine(line)
            }

            // Skip the detached-HEAD pseudo-row git emits in `branch --list`
            // when HEAD is detached. It carries a synthetic refname like
            // `(HEAD detached at abc1234)` that is not a real ref.
            if fullName.hasPrefix("(") {
                continue
            }

            let isRemote = fullName.hasPrefix("refs/remotes/")
            let remote: String? = isRemote ? extractRemoteName(fromFullRef: fullName) : nil
            let upstream = upstreamRaw.isEmpty ? nil : upstreamRaw
            let isGone = trackRaw.contains("gone")
            let ahead: Int?
            let behind: Int?
            if upstream == nil {
                ahead = nil
                behind = nil
            } else {
                ahead = parseInt(in: trackRaw, after: "ahead ") ?? 0
                behind = parseInt(in: trackRaw, after: "behind ") ?? 0
            }
            let isHead = headMarker == "*"

            branches.append(Branch(
                shortName: shortName,
                fullName: fullName,
                sha: sha,
                upstream: upstream,
                isRemote: isRemote,
                remote: remote,
                ahead: ahead,
                behind: behind,
                isGone: isGone,
                isHead: isHead
            ))
        }

        return branches
    }

    // MARK: - Private

    /// Extracts "origin" from "refs/remotes/origin/main" or
    /// "refs/remotes/origin/feature/x" (nested branch names allowed).
    private static func extractRemoteName(fromFullRef ref: String) -> String? {
        let prefix = "refs/remotes/"
        guard ref.hasPrefix(prefix) else { return nil }
        let remainder = ref.dropFirst(prefix.count)
        guard let slash = remainder.firstIndex(of: "/") else { return nil }
        return String(remainder[..<slash])
    }

    private static func parseInt(in source: String, after prefix: String) -> Int? {
        guard let range = source.range(of: prefix) else { return nil }
        let digits = source[range.upperBound...].prefix(while: { $0.isNumber })
        return Int(digits)
    }
}
