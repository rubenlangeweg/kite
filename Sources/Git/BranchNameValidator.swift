import Foundation

/// Pure validator for user-entered branch names. Implements a practical subset
/// of `git check-ref-format --branch <name>` — enough to reject the common +
/// tricky cases that cause `git switch -c <name>` to bail with a ref-format
/// error, and to block shell-metacharacter-looking input before it reaches a
/// subprocess.
///
/// Design notes:
///   - Pure (no side effects, no I/O) so it composes with SwiftUI onChange
///     handlers without async noise.
///   - Returns `ValidationError?` rather than throwing so the view layer can
///     render inline error text without try/catch gymnastics.
///   - Shell safety: `Process` uses argv (not a shell), so a branch name
///     with a `;` would never be interpreted as a command separator. The
///     validator still rejects `;` (via .containsDisallowedChar for the few
///     shell-ish ones we catch) because git itself forbids many such
///     characters in ref names. VAL-SEC-007 evidence.
enum BranchNameValidator {
    /// Validation failures. Each case carries user-facing copy via
    /// `LocalizedError.errorDescription`.
    enum ValidationError: Error, Equatable, LocalizedError {
        case empty
        case containsControlCharacter
        case containsSpace
        case containsDisallowedChar(Character)
        case leadsWithDash
        case containsDotDot
        case containsAtBrace
        case endsWithDot
        case endsWithSlash
        case endsWithLock
        case containsSlashDot
        case containsDoubleSlash
        case reserved

        var errorDescription: String? {
            switch self {
            case .empty:
                "Branch name cannot be empty."
            case .containsControlCharacter:
                "Branch name cannot contain control characters."
            case .containsSpace:
                "Branch name cannot contain spaces."
            case let .containsDisallowedChar(char):
                "Branch name cannot contain \u{201C}\(char)\u{201D}."
            case .leadsWithDash:
                "Branch name cannot start with \u{201C}-\u{201D}."
            case .containsDotDot:
                "Branch name cannot contain \u{201C}..\u{201D}."
            case .containsAtBrace:
                "Branch name cannot contain \u{201C}@{\u{201D}."
            case .endsWithDot:
                "Branch name cannot end with \u{201C}.\u{201D}."
            case .endsWithSlash:
                "Branch name cannot end with \u{201C}/\u{201D}."
            case .endsWithLock:
                "Branch name cannot end with \u{201C}.lock\u{201D}."
            case .containsSlashDot:
                "Branch name cannot contain a component starting with \u{201C}.\u{201D}."
            case .containsDoubleSlash:
                "Branch name cannot contain \u{201C}//\u{201D}."
            case .reserved:
                "Branch name is reserved."
            }
        }
    }

    /// Names git's ref plumbing treats specially. We reject these outright so
    /// a user can't ask us to create `HEAD` and confuse every tool that looks
    /// at `.git/`.
    private static let reservedNames: Set<String> = [
        "HEAD",
        "FETCH_HEAD",
        "ORIG_HEAD",
        "MERGE_HEAD"
    ]

    /// Characters git's ref-format rules forbid anywhere in a ref name.
    /// Space is checked separately to surface the dedicated `.containsSpace`
    /// error. Backslash is included — `\` is not legal in a ref component.
    private static let disallowedCharacters: [Character] = [
        "~", "^", ":", "?", "*", "[", "\\"
    ]

    /// Validate a candidate branch name. Returns `nil` on success; a specific
    /// `ValidationError` on failure. The first matching rule wins — order is
    /// chosen so that the most user-actionable error surfaces first.
    ///
    /// The rule ladder is split across helpers to keep this function under
    /// SwiftLint's cyclomatic_complexity threshold.
    static func validate(_ name: String) -> ValidationError? {
        if let err = structuralError(in: name) { return err }
        if let err = characterError(in: name) { return err }
        if let err = sequenceError(in: name) { return err }
        if let err = endingError(in: name) { return err }
        if reservedNames.contains(name) { return .reserved }
        return nil
    }

    /// Empty / leading-dash checks that don't need a character scan.
    private static func structuralError(in name: String) -> ValidationError? {
        if name.isEmpty { return .empty }
        if name.first == "-" { return .leadsWithDash }
        return nil
    }

    /// Per-character scan: control chars, space, and disallowed characters.
    private static func characterError(in name: String) -> ValidationError? {
        for scalar in name.unicodeScalars where scalar.value <= 0x1f || scalar.value == 0x7f {
            return .containsControlCharacter
        }
        for char in name {
            if char == " " { return .containsSpace }
            if disallowedCharacters.contains(char) {
                return .containsDisallowedChar(char)
            }
        }
        return nil
    }

    /// Two-character illegal sequences anywhere in the name.
    private static func sequenceError(in name: String) -> ValidationError? {
        if name.contains("..") { return .containsDotDot }
        if name.contains("@{") { return .containsAtBrace }
        if name.contains("/.") { return .containsSlashDot }
        if name.contains("//") { return .containsDoubleSlash }
        return nil
    }

    /// Illegal suffix checks: `.`, `/`, and `.lock`.
    private static func endingError(in name: String) -> ValidationError? {
        if name.hasSuffix(".") { return .endsWithDot }
        if name.hasSuffix("/") { return .endsWithSlash }
        if name.hasSuffix(".lock") { return .endsWithLock }
        return nil
    }
}
