import SwiftUI

/// Bottom-aligned stack of toast banners. Overlaid on `RootView`'s
/// `NavigationSplitView` so toasts float above the three-pane layout without
/// stealing focus.
///
/// Newest toast renders at the bottom of the stack (closest to the user's
/// cursor / window chrome). `ToastCenter` already inserts newest-first into
/// its `toasts` array; this view renders top-to-bottom, so we flip to
/// bottom-align and keep array order. The transition animates the newest
/// toast sliding up from the bottom edge.
///
/// Fulfills: VAL-UI-004 (toasts at bottom).
struct ToastHostView: View {
    @Environment(ToastCenter.self) private var center

    var body: some View {
        VStack(spacing: 8) {
            ForEach(center.toasts) { toast in
                ToastRow(toast: toast) {
                    center.dismiss(toast.id)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityIdentifier("Toast.\(toast.kind == .success ? "success" : "error").\(toast.id.uuidString)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(.easeInOut(duration: 0.25), value: center.toasts)
        .allowsHitTesting(true)
        .accessibilityIdentifier("Toast.Host")
    }
}

/// Presentational toast row. Pure inputs + single `onDismiss` callback.
/// Stateful "is detail expanded" is local to the row — collapses when the
/// toast leaves the stack.
struct ToastRow: View {
    let toast: Toast
    let onDismiss: () -> Void

    @State private var isDetailExpanded: Bool = false

    // MARK: - Layout constants

    private static let maxWidth: CGFloat = 540
    private static let detailMaxHeight: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            if isDetailExpanded, let detail = toast.detail {
                detailBlock(detail)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: Self.maxWidth, alignment: .leading)
        .background(backgroundShape)
        .overlay(borderShape)
        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
        .contentShape(Rectangle())
        .onTapGesture {
            // Error toasts expand/collapse their detail on row tap.
            // Success toasts have no detail interaction.
            guard toast.kind == .error, toast.detail != nil else { return }
            isDetailExpanded.toggle()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: iconSystemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.message)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if toast.kind == .error, toast.detail != nil {
                    Text(isDetailExpanded ? "Hide details" : "Show details")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if toast.kind == .error {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss toast")
                .accessibilityIdentifier("Toast.DismissButton")
            }
        }
    }

    private func detailBlock(_ detail: String) -> some View {
        ScrollView {
            Text(detail)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(maxHeight: Self.detailMaxHeight)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.08))
        )
        .padding(.top, 8)
        .accessibilityIdentifier("Toast.Detail")
    }

    // MARK: - Style helpers

    private var iconSystemName: String {
        switch toast.kind {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch toast.kind {
        case .success: .green
        case .error: .red
        }
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(tintedFill)
    }

    private var borderShape: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(borderStroke, lineWidth: 0.5)
    }

    private var tintedFill: Color {
        switch toast.kind {
        case .success: Color.green.opacity(0.18)
        case .error: Color.red.opacity(0.18)
        }
    }

    private var borderStroke: Color {
        switch toast.kind {
        case .success: Color.green.opacity(0.45)
        case .error: Color.red.opacity(0.45)
        }
    }
}
