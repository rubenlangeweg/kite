import Foundation
import Testing
@testable import Kite

/// Exhaustive coverage for `BranchNameValidator.validate(_:)`.
///
/// Fulfills: VAL-BRANCHOP-002 (invalid names rejected inline with specific
/// messages), VAL-SEC-007 (shell-metacharacter-ish input blocked before it
/// reaches `Process`).
@Suite("BranchNameValidator")
struct BranchNameValidatorTests {
    // MARK: - Passing fixtures

    /// Representative set of branch names git accepts. Each must return `nil`.
    @Test(
        "accepts valid branch names",
        arguments: [
            "main",
            "master",
            "feature/x",
            "feature/v1-foo",
            "release/2025.04",
            "name.thing",
            "A_B-C.123",
            "fix_issue_42",
            "v1.2.3-beta",
            "dev"
        ]
    )
    func acceptsValidNames(_ name: String) {
        #expect(BranchNameValidator.validate(name) == nil, "expected \(name) to be valid")
    }

    // MARK: - Failing fixtures (table-driven)

    /// Every documented failure mode. Expressed as `(input, expected error)`
    /// pairs so each regression points at a single assertion.
    @Test(
        "rejects invalid branch names with the matching error",
        arguments: [
            ("", BranchNameValidator.ValidationError.empty),
            (" ", BranchNameValidator.ValidationError.containsSpace),
            ("name with spaces", BranchNameValidator.ValidationError.containsSpace),
            ("-foo", BranchNameValidator.ValidationError.leadsWithDash),
            ("foo~bar", BranchNameValidator.ValidationError.containsDisallowedChar("~")),
            ("foo^bar", BranchNameValidator.ValidationError.containsDisallowedChar("^")),
            ("foo:bar", BranchNameValidator.ValidationError.containsDisallowedChar(":")),
            ("foo?bar", BranchNameValidator.ValidationError.containsDisallowedChar("?")),
            ("foo*bar", BranchNameValidator.ValidationError.containsDisallowedChar("*")),
            ("foo[bar", BranchNameValidator.ValidationError.containsDisallowedChar("[")),
            ("foo\\bar", BranchNameValidator.ValidationError.containsDisallowedChar("\\")),
            ("foo..bar", BranchNameValidator.ValidationError.containsDotDot),
            ("foo@{bar", BranchNameValidator.ValidationError.containsAtBrace),
            ("foo.", BranchNameValidator.ValidationError.endsWithDot),
            ("foo/", BranchNameValidator.ValidationError.endsWithSlash),
            ("foo.lock", BranchNameValidator.ValidationError.endsWithLock),
            ("foo/.bar", BranchNameValidator.ValidationError.containsSlashDot),
            ("foo//bar", BranchNameValidator.ValidationError.containsDoubleSlash),
            ("HEAD", BranchNameValidator.ValidationError.reserved),
            ("FETCH_HEAD", BranchNameValidator.ValidationError.reserved),
            ("ORIG_HEAD", BranchNameValidator.ValidationError.reserved),
            ("MERGE_HEAD", BranchNameValidator.ValidationError.reserved),
        ]
    )
    func rejectsInvalidNames(_ input: String, _ expected: BranchNameValidator.ValidationError) {
        #expect(
            BranchNameValidator.validate(input) == expected,
            "expected \(input) → \(expected)"
        )
    }

    // MARK: - Control character cases (can't fit cleanly in the table above)

    @Test("rejects tab as a control character")
    func rejectsTab() {
        #expect(BranchNameValidator.validate("foo\tbar") == .containsControlCharacter)
    }

    @Test("rejects newline as a control character")
    func rejectsNewline() {
        #expect(BranchNameValidator.validate("foo\nbar") == .containsControlCharacter)
    }

    @Test("rejects NUL as a control character")
    func rejectsNul() {
        #expect(BranchNameValidator.validate("foo\0bar") == .containsControlCharacter)
    }

    @Test("rejects DEL (0x7f) as a control character")
    func rejectsDel() {
        #expect(BranchNameValidator.validate("foo\u{7F}bar") == .containsControlCharacter)
    }

    // MARK: - Shell-metacharacter-shaped input (VAL-SEC-007)

    /// VAL-SEC-007: The core defence against shell injection is the
    /// `Process` argv model — a branch name like `x; touch /tmp/pwn` would
    /// be passed to `/usr/bin/git` as a single argument, never parsed by a
    /// shell. The validator's job is to enforce git's ref-format rules, not
    /// to blacklist every shell metacharacter.
    ///
    /// Names that git ref-format would reject (containing space, `~`, `^`,
    /// `:`, `?`, `*`, `[`, `\\`) are rejected by the validator. Names that
    /// are legal refs but contain shell-ish characters (`;`, `&`, `` ` ``,
    /// `$`, `|`, `>`, `<`) may or may not be rejected — they're safe either
    /// way because argv forbids reinterpretation.
    @Test(
        "validator rejects shell-shaped names that contain git-forbidden chars",
        arguments: [
            "x; touch /tmp/pwn", // rejected for containing space
            "x && rm -rf /", // rejected for containing space
            "x*cat", // rejected for containing "*"
            "x?foo", // rejected for containing "?"
            "x~foo", // rejected for containing "~"
            "x^foo", // rejected for containing "^"
            "x:foo", // rejected for containing ":"
            "x[foo", // rejected for containing "["
        ]
    )
    func rejectsGitForbiddenCharsInShellShapedNames(_ name: String) {
        #expect(
            BranchNameValidator.validate(name) != nil,
            "validator should reject git-forbidden input: \(name)"
        )
    }

    // MARK: - Error messages are user-facing

    @Test("every error case has a non-empty errorDescription")
    func everyCaseHasDescription() {
        let cases: [BranchNameValidator.ValidationError] = [
            .empty,
            .containsControlCharacter,
            .containsSpace,
            .containsDisallowedChar("~"),
            .leadsWithDash,
            .containsDotDot,
            .containsAtBrace,
            .endsWithDot,
            .endsWithSlash,
            .endsWithLock,
            .containsSlashDot,
            .containsDoubleSlash,
            .reserved
        ]
        for err in cases {
            let desc = err.errorDescription ?? ""
            #expect(!desc.isEmpty, "\(err) has empty errorDescription")
        }
    }
}
