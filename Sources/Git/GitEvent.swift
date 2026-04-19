import Foundation

/// Events yielded by `Git.stream`. Progress parsing (percent extraction) is
/// NOT done here — consumers interested in progress pipe `stderrLine` values
/// through `ProgressParser` (M1-git-parsers).
enum GitEvent: Equatable {
    case stdoutLine(String)
    case stderrLine(String)
    case completed(exitCode: Int32)
}
