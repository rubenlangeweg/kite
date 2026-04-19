import Foundation

/// Stateful parser for git fetch/push/clone stderr progress lines.
///
/// Git writes progress using `\r` to overwrite the same terminal line, e.g.:
///
/// ```
/// remote: Counting objects:  50% (21/42)\r
/// remote: Counting objects: 100% (42/42), done.\r
/// Receiving objects:  42% (840/2000)\r
/// ```
///
/// Callers push raw chunks in via `consume(_:)`. The parser:
///
///   - Splits on `\r` and `\n`.
///   - Recognises `(remote: )?<phase>: <percent>% (...)` patterns.
///   - Deduplicates within the same phase at the same percent (`\r`-updated
///     lines produce one event per distinct (phase, percent) pair).
///
/// Lines that don't match the progress shape return `nil`. The `raw` field
/// of emitted events is the original source line so callers can log the
/// exact bytes they received.
///
/// Fulfills VAL-PARSE-006.
final class ProgressParser {
    /// Lingering text from an incomplete chunk (didn't end on `\r` or `\n`).
    private var carry: String = ""

    /// Most recently emitted (phase, percent) — used to suppress duplicate
    /// `\r`-updates that report the same state.
    private var lastEmitted: (phase: String, percent: Int?)?

    init() {}

    /// Feed a raw stderr chunk. Returns the latest progress event observed in
    /// this chunk (if any). Earlier events in the same chunk are still
    /// processed (their phase/percent update internal state) but only the
    /// final event is returned — this matches the 10 Hz coalescing guidance
    /// in `library/git-cli-integration.md` §8.
    @discardableResult
    func consume(_ raw: String) -> ProgressEvent? {
        carry += raw

        // Split on BOTH \r and \n. `split(whereSeparator:)` drops empties
        // which is what we want for consecutive separators.
        let pieces = carry.split(whereSeparator: { $0 == "\r" || $0 == "\n" })
            .map(String.init)

        // If the chunk ended cleanly on a separator, consume all pieces.
        // Otherwise the last piece is a partial line — keep it buffered.
        let endedOnSeparator = raw.last == "\r" || raw.last == "\n"
        let completePieces: [String]
        if endedOnSeparator {
            completePieces = pieces
            carry = ""
        } else if let tail = pieces.last {
            completePieces = Array(pieces.dropLast())
            carry = tail
        } else {
            completePieces = []
            carry = ""
        }

        var latest: ProgressEvent?
        for piece in completePieces {
            if let event = event(for: piece) {
                latest = event
            }
        }
        return latest
    }

    // MARK: - Private

    private func event(for line: String) -> ProgressEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }

        // Strip leading "remote: " for parsing, but keep it in `raw`.
        var body = trimmed
        if body.hasPrefix("remote: ") {
            body = String(body.dropFirst("remote: ".count))
        }

        // Phase is everything up to the first ": ".
        guard let colonRange = body.range(of: ": ") else {
            return nil
        }
        let phase = String(body[..<colonRange.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        let rest = body[colonRange.upperBound...]

        // Must look phase-y: ASCII letters + spaces only.
        if phase.isEmpty { return nil }
        if !phase.allSatisfy({ $0.isLetter || $0 == " " }) {
            return nil
        }

        let percent = extractPercent(from: rest)

        // Dedup: same (phase, percent) as last emitted → drop.
        if let last = lastEmitted, last.phase == phase, last.percent == percent {
            return nil
        }
        lastEmitted = (phase, percent)

        return ProgressEvent(phase: phase, percent: percent, raw: line)
    }

    private func extractPercent(from rest: some StringProtocol) -> Int? {
        // Find the first "<digits>%" token.
        let view = String(rest)
        guard let percentIdx = view.firstIndex(of: "%") else { return nil }
        // Walk back collecting digits until we hit a non-digit.
        var cursor = percentIdx
        var digits = ""
        while cursor > view.startIndex {
            let before = view.index(before: cursor)
            let ch = view[before]
            if ch.isNumber {
                digits.insert(ch, at: digits.startIndex)
                cursor = before
            } else {
                break
            }
        }
        return Int(digits)
    }
}
