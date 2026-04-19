import Foundation

/// Parses `git log --all --topo-order --format='%H%x00%P%x00%an%x00%ae%x00%at%x00%s' -z` output.
///
/// With `-z`, the record terminator becomes `\0` (instead of `\n`). Combined
/// with `%x00` field separators, the entire output is a flat NUL-delimited
/// stream of 6N fields. The parser walks fields in chunks of 6.
///
/// `%P` is space-separated parent SHAs, or empty for a root commit. Merges
/// have 2+ parents; octopus merges 3+. Unicode subjects are passed through
/// verbatim.
///
/// Fulfills VAL-PARSE-002.
enum LogParser {
    private static let fieldsPerRecord = 6

    static func parse(_ input: String) throws -> [Commit] {
        if input.isEmpty { return [] }

        // Do NOT omit empty subsequences — an empty `%P` (root commit) is a
        // legitimate zero-length field that we must preserve by position.
        let fields = input.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)

        // `-z` terminates the final record with a trailing `\0`, which produces
        // one extra empty element. Drop it before the modulo check.
        var effective = fields
        if effective.last == "" {
            effective.removeLast()
        }
        if effective.isEmpty { return [] }

        guard effective.count % fieldsPerRecord == 0 else {
            throw ParseError.unrecognizedFormat(
                "log field count \(effective.count) is not a multiple of \(fieldsPerRecord)"
            )
        }

        var commits: [Commit] = []
        commits.reserveCapacity(effective.count / fieldsPerRecord)

        var offset = 0
        while offset < effective.count {
            let sha = effective[offset]
            let parentsRaw = effective[offset + 1]
            let authorName = effective[offset + 2]
            let authorEmail = effective[offset + 3]
            let timestampRaw = effective[offset + 4]
            let subject = effective[offset + 5]

            if sha.isEmpty {
                throw ParseError.malformedLine(
                    "log record has empty SHA at field offset \(offset)"
                )
            }
            guard let unixSeconds = TimeInterval(timestampRaw) else {
                throw ParseError.invalidField(field: "authoredAt", value: timestampRaw)
            }

            let parents: [String] = if parentsRaw.isEmpty {
                []
            } else {
                parentsRaw.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            }

            commits.append(Commit(
                sha: sha,
                parents: parents,
                authorName: authorName,
                authorEmail: authorEmail,
                authoredAt: Date(timeIntervalSince1970: unixSeconds),
                subject: subject
            ))

            offset += fieldsPerRecord
        }

        return commits
    }
}
