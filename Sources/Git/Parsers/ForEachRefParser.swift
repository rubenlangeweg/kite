import Foundation

/// Parses `git for-each-ref --format='%(objectname) %(refname)%00%(*objectname)'`
/// output into a `[sha: [RefKind]]` map used to attach branch/tag pills to
/// commits in the graph.
///
/// Format per line: `<objectname> <refname>\x00<peeled-objectname>`.
///   - For lightweight tags and branches, `<peeled-objectname>` is empty and
///     we key on `<objectname>`.
///   - For annotated tags, `<objectname>` is the tag-object SHA and
///     `<peeled-objectname>` is the underlying commit SHA — we key on the
///     latter so the tag pill renders on the commit node.
///
/// Symbolic HEAD pseudo-refs (e.g. `refs/remotes/origin/HEAD`, or a bare
/// `HEAD`) are intentionally excluded.
///
/// Fulfills VAL-PARSE-004.
enum ForEachRefParser {
    static func parse(_ input: String) throws -> [String: [RefKind]] {
        if input.isEmpty { return [:] }

        var map: [String: [RefKind]] = [:]

        for rawLine in input.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)

            // Split on NUL into (prefix, peeled). The prefix carries
            // "<sha> <refname>" separated by a single space.
            let nulSplit = line.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard nulSplit.count >= 1 else {
                throw ParseError.malformedLine(line)
            }
            let head = nulSplit[0]
            let peeled = nulSplit.count >= 2 ? nulSplit[1] : ""

            guard let spaceIdx = head.firstIndex(of: " ") else {
                throw ParseError.malformedLine(line)
            }
            let objectname = String(head[..<spaceIdx])
            let refname = String(head[head.index(after: spaceIdx)...])

            if objectname.isEmpty || refname.isEmpty {
                throw ParseError.malformedLine(line)
            }

            // Exclude symbolic HEAD pseudo-refs.
            if refname == "HEAD" || refname.hasSuffix("/HEAD") {
                continue
            }

            guard let kind = classify(refname: refname) else {
                // Unknown ref prefix — skip (forward-compatible with e.g.
                // refs/notes, refs/stash, refs/pull/*).
                continue
            }

            // Annotated tags: key on peeled commit SHA when present.
            let keySha = peeled.isEmpty ? objectname : peeled
            map[keySha, default: []].append(kind)
        }

        return map
    }

    // MARK: - Private

    private static func classify(refname: String) -> RefKind? {
        if refname.hasPrefix("refs/heads/") {
            return .localBranch(String(refname.dropFirst("refs/heads/".count)))
        }
        if refname.hasPrefix("refs/remotes/") {
            let rest = refname.dropFirst("refs/remotes/".count)
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            let remote = String(rest[..<slash])
            let branch = String(rest[rest.index(after: slash)...])
            if branch.isEmpty { return nil }
            return .remoteBranch(remote: remote, branch: branch)
        }
        if refname.hasPrefix("refs/tags/") {
            return .tag(String(refname.dropFirst("refs/tags/".count)))
        }
        return nil
    }
}
