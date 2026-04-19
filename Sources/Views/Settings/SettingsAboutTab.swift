import SwiftUI

/// Minimal About tab. App icon + bundle-version lookup lands in
/// M8-app-icon-and-plist; this is just enough to satisfy the three-tab shape
/// required for VAL-UI-008.
struct SettingsAboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Kite")
                .font(.title2).fontWeight(.semibold)

            Text(versionLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Native macOS git client for daily basic-flow work.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("Settings.About")
    }

    /// "Version X.Y (Z)" sourced from the main bundle. Falls back to "dev" in
    /// unusual hosts (SwiftUI previews, command-line test bundles) that don't
    /// surface the expected Info.plist keys.
    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "Version \(marketing) (\(build))"
    }
}
