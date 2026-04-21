import Foundation
import Observation

/// A single tracked long-running op displayed by `ToolbarProgressIndicator`.
/// `percent == nil` → indeterminate spinner; otherwise 0..100 linear bar.
struct ProgressItem: Identifiable, Equatable {
    let id: UUID
    let label: String
    var percent: Int?

    init(id: UUID = UUID(), label: String, percent: Int? = nil) {
        self.id = id
        self.label = label
        self.percent = percent
    }
}

/// App-wide progress surface. Fetch/pull/push (M5-fetch, M5-pull-push) begin
/// a tracked op, stream updates parsed from `git` stderr into `update(_:)`,
/// and `end(_:)` when the process exits — successful or otherwise.
///
/// `ToolbarProgressIndicator` observes `active` and renders the first item
/// in an indeterminate circular spinner (percent nil) or a linear
/// determinate bar (percent set). Fulfills: VAL-UI-006.
@Observable
@MainActor
final class ProgressCenter {
    private(set) var active: [ProgressItem] = []

    var isActive: Bool {
        !active.isEmpty
    }

    init() {}

    /// Start a new tracked op. Returns an opaque handle — the caller MUST
    /// call `end(_:)` when the op finishes to avoid a permanent toolbar
    /// spinner.
    @discardableResult
    func begin(label: String) -> ProgressItem.ID {
        let item = ProgressItem(label: label)
        active.append(item)
        return item.id
    }

    /// Adjust percent for a running op. Pass nil to flip the indicator back
    /// to indeterminate (useful when a determinate parser can't keep up with
    /// e.g. the "Resolving deltas" phase of a fetch).
    func update(_ id: ProgressItem.ID, percent: Int?) {
        guard let idx = active.firstIndex(where: { $0.id == id }) else { return }
        active[idx].percent = percent
    }

    /// End the op. Safe to call for an already-ended id.
    func end(_ id: ProgressItem.ID) {
        active.removeAll { $0.id == id }
    }
}
