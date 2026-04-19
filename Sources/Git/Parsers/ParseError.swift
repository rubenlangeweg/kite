import Foundation

/// Errors thrown by the porcelain parsers when input is malformed.
///
/// Each case carries the offending snippet so unit tests and error toasts
/// can show what git produced that we couldn't parse.
enum ParseError: Error, Equatable {
    case malformedLine(String)
    case unexpectedEmpty
    case unrecognizedFormat(String)
    case invalidField(field: String, value: String)
}

extension ParseError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .malformedLine(line):
            "Malformed line: \(line)"
        case .unexpectedEmpty:
            "Unexpected empty input."
        case let .unrecognizedFormat(snippet):
            "Unrecognized format: \(snippet)"
        case let .invalidField(field, value):
            "Invalid field \(field): \(value)"
        }
    }
}
