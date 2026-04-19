import Foundation

/// A single progress update parsed from git fetch/push/clone stderr.
///
/// `percent` is nil when git emitted a status line without a percentage
/// (e.g. `remote: Enumerating objects: 42, done.`). `raw` preserves the
/// source line verbatim so callers can log the exact bytes received.
struct ProgressEvent: Equatable {
    let phase: String
    let percent: Int?
    let raw: String
}
