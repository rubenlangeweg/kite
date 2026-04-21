import Foundation
import Observation

/// A single toast banner rendered by `ToastHostView`.
///
/// Two kinds:
///   - `.success` — auto-dismissed by `ToastCenter` 5s after insertion.
///   - `.error` — sticky; user must click ✕ or call `dismiss(_:)`.
///
/// `detail` carries the optional full stderr blob surfaced when the user
/// expands an error toast (VAL-UI-005).
struct Toast: Identifiable, Equatable {
    enum Kind: Equatable {
        case success
        case error
    }

    let id: UUID
    let kind: Kind
    let message: String
    let detail: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        kind: Kind,
        message: String,
        detail: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.message = message
        self.detail = detail
        self.createdAt = createdAt
    }
}

/// App-wide toast surface. Every subsystem that wants to notify the user
/// (fetch/pull/push, auto-fetch, branch ops) enqueues through this observable
/// so `ToastHostView` can render a single consistent stack.
///
/// Semantics (see M5-toast-infrastructure spec):
///   - `success(_:detail:)` auto-dismisses after 5s via the monotonic-tick
///     pattern (`SettingsRootsTab.showInlineError` precedent). Race-free
///     against rapid re-triggers — the scheduled dismissal only fires when
///     the per-toast tick still matches.
///   - `error(_:detail:)` is sticky; the user must ✕ or call `dismiss`.
///   - Newest toasts insert at the front of `toasts` so the stack grows
///     downward with the latest on top.
///   - The visible success count is capped at 3 — a 4th success pushes the
///     oldest success out early. Error toasts are never evicted.
///
/// Fulfills: VAL-UI-004 (bottom toasts), VAL-UI-005 (sticky error + detail).
@Observable
@MainActor
final class ToastCenter {
    private(set) var toasts: [Toast] = []

    /// Monotonic counter incremented each time a success toast is scheduled
    /// for auto-dismissal. We scope the "should this timer still fire?" check
    /// to a per-toast tick so rapid re-triggers don't clobber a toast that
    /// was explicitly dismissed or superseded in between.
    ///
    /// `@ObservationIgnored` so view redraws don't re-observe a counter
    /// that changes on every toast enqueue.
    @ObservationIgnored
    private var autoDismissTicks: [UUID: Int] = [:]

    @ObservationIgnored
    private var tickCounter: Int = 0

    /// Max concurrently visible success toasts. Errors don't count toward
    /// this cap.
    private let maxVisibleSuccess: Int = 3

    /// Default auto-dismiss delay for success toasts, in nanoseconds. Factored
    /// out so tests (if they ever need to) can override without magic numbers.
    @ObservationIgnored
    private let autoDismissNanos: UInt64 = 5_000_000_000

    init() {}

    /// Show a green success toast. Dismisses itself 5s later unless the user
    /// or another `dismiss(_:)` call takes it down first.
    func success(_ message: String, detail: String? = nil) {
        let toast = Toast(kind: .success, message: message, detail: detail)
        insert(toast)
        enforceSuccessCap()
        scheduleAutoDismiss(toast.id)
    }

    /// Show a red sticky error toast. Never auto-dismisses — user must
    /// interact to remove it.
    func error(_ message: String, detail: String? = nil) {
        let toast = Toast(kind: .error, message: message, detail: detail)
        insert(toast)
    }

    /// Remove a specific toast by id. No-op if it already fell out.
    func dismiss(_ id: Toast.ID) {
        toasts.removeAll { $0.id == id }
        autoDismissTicks.removeValue(forKey: id)
    }

    // MARK: - Internals

    private func insert(_ toast: Toast) {
        // Newest on top: prepend at index 0. `ToastHostView` renders the
        // array top-to-bottom and the overlay is bottom-aligned, so the
        // newest ends up visually at the bottom — the UX intent for "latest
        // notification nearest the user's attention."
        toasts.insert(toast, at: 0)
    }

    private func enforceSuccessCap() {
        // Count successes from newest → oldest; once we pass the cap, drop
        // the oldest surplus ones. Errors are skipped (never evicted).
        var successesSeen = 0
        var idsToDrop: [UUID] = []
        for toast in toasts where toast.kind == .success {
            successesSeen += 1
            if successesSeen > maxVisibleSuccess {
                idsToDrop.append(toast.id)
            }
        }
        for id in idsToDrop {
            dismiss(id)
        }
    }

    private func scheduleAutoDismiss(_ id: Toast.ID) {
        tickCounter &+= 1
        let mine = tickCounter
        autoDismissTicks[id] = mine
        let delay = autoDismissNanos
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            // Fire only if THIS scheduling is still the live one. A later
            // enforceSuccessCap() eviction or an explicit dismiss() removes
            // the entry, invalidating this timer.
            if autoDismissTicks[id] == mine {
                dismiss(id)
            }
        }
    }
}
