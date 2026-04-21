import SwiftUI

/// Modal sheet that collects a new branch name and passes it back to the
/// caller. Validation runs on every keystroke via `BranchNameValidator`; the
/// "Create branch" button stays disabled until the field is non-empty AND
/// the validator returns `nil`.
///
/// Pure presentational — no `@Environment` state, no subprocess work. The
/// outer `NewBranchButton` owns `BranchOps` and dispatches `onCreate`.
/// Snapshot tests exercise this view directly.
///
/// Fulfills: VAL-BRANCHOP-001 (sheet prompt), VAL-BRANCHOP-002 (inline
/// ref-format rejection with specific messages).
struct NewBranchSheet: View {
    let currentBranch: String?
    let onCreate: (String) async -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var validationError: String?
    @State private var isSubmitting: Bool = false
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New branch")
                .font(.headline)
                .accessibilityIdentifier("NewBranchSheet.Title")

            if let current = currentBranch {
                Text("Branch will fork from \u{201C}\(current)\u{201D}.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("NewBranchSheet.ForkSource")
            }

            TextField("branch-name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFieldFocused)
                .disabled(isSubmitting)
                .accessibilityIdentifier("NewBranchSheet.NameField")
                .onSubmit {
                    submit()
                }
                .onChange(of: name) { _, newValue in
                    validationError = BranchNameValidator.validate(newValue)?.errorDescription
                }

            if let err = validationError, !name.isEmpty {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("NewBranchSheet.ValidationError")
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isSubmitting)
                .accessibilityIdentifier("NewBranchSheet.Cancel")

                Spacer()

                Button("Create branch") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitDisabled)
                .accessibilityIdentifier("NewBranchSheet.Create")
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            nameFieldFocused = true
        }
        .accessibilityIdentifier("NewBranchSheet")
    }

    /// Derived disabled-state for the Create button. Captured in a computed
    /// property so both the Create button and onSubmit agree on the rule.
    private var isSubmitDisabled: Bool {
        name.isEmpty || validationError != nil || isSubmitting
    }

    /// Kick off the async `onCreate` callback, guarding against rapid
    /// double-submits (Enter + click). `isSubmitting` latches for the
    /// sheet's remaining life — the parent is expected to dismiss the sheet
    /// on outcome rather than let it re-arm.
    private func submit() {
        guard !isSubmitDisabled else { return }
        let candidate = name
        isSubmitting = true
        Task {
            await onCreate(candidate)
            // Keep `isSubmitting` latched: a success dismisses the sheet
            // (state dies with it), a failure keeps the user's typed text
            // visible behind the failing toast and the parent can re-present
            // the sheet with a fresh state instance.
        }
    }
}
