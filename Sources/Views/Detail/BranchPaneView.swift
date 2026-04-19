import SwiftUI

/// Composition wrapper for the middle column's upper pane.
///
/// Stacks the compact working-tree `StatusHeaderView` above the existing
/// `BranchListView`, separated by a divider. `RootView` drops this in place
/// of `BranchListView` directly so both views share the same middle-column
/// envelope and resize together in the `VSplitView`.
///
/// The two children are independent: each owns its own `@Observable` model
/// and reloads on the same focus/FSWatcher signals, but they do not talk to
/// each other (no shared state, no cross-observation).
struct BranchPaneView: View {
    var body: some View {
        VStack(spacing: 0) {
            StatusHeaderView()
            Divider()
            BranchListView()
        }
        .accessibilityIdentifier("BranchPane")
    }
}
