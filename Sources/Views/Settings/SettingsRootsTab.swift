import AppKit
import SwiftUI

/// Roots tab: lists the default `~/Developer` scan root plus any extra roots
/// configured via `NSOpenPanel`. Each row shows on-disk status and an action
/// column; extra rows have a Remove button, the default row's Remove is
/// disabled with a tooltip.
///
/// Fulfills VAL-REPO-003 (extra roots scanned), VAL-REPO-004 (removed roots
/// stop scanning), VAL-REPO-005 (invalid path surfaced inline).
struct SettingsRootsTab: View {
    @Environment(PersistenceStore.self) private var persistence
    @Environment(RepoSidebarModel.self) private var sidebarModel

    @State private var rootsModel: SettingsRootsModel?
    @State private var inlineError: String?
    /// Monotonic counter used to key animated error dismissals so consecutive
    /// errors retrigger the fade animation.
    @State private var errorTick: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Table(effectiveRows) {
                TableColumn("Path") { row in
                    Text(row.displayPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(row.path)
                        .accessibilityIdentifier("Settings.Roots.Path.\(row.path)")
                }

                TableColumn("Status") { row in
                    statusBadge(for: row)
                }
                .width(min: 96, ideal: 110, max: 140)

                TableColumn("Actions") { row in
                    HStack(spacing: 6) {
                        Button("Scan now") {
                            Task { await sidebarModel.refresh() }
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("Settings.Roots.ScanNow.\(row.path)")

                        Button(role: .destructive) {
                            handleRemove(row: row)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .disabled(row.isDefault)
                        .help(row.isDefault ? "Default root" : "Remove this root")
                        .accessibilityIdentifier("Settings.Roots.Remove.\(row.path)")
                    }
                }
                .width(min: 150, ideal: 160, max: 200)
            }
            .accessibilityIdentifier("Settings.Roots.Table")
            .frame(minHeight: 160)

            footer
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("Settings.Roots")
        .onAppear {
            if rootsModel == nil {
                rootsModel = SettingsRootsModel(persistence: persistence)
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Scan roots")
                    .font(.headline)

                Spacer()

                Button {
                    Task { await sidebarModel.refresh() }
                } label: {
                    Label("Scan now", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                }
                .accessibilityIdentifier("Settings.Roots.ScanAll")
            }

            Text("Kite scans these folders for git repositories. The default scan path is `~/Developer`.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    handleAddFolder()
                } label: {
                    Label("Add folder…", systemImage: "folder.badge.plus")
                }
                .accessibilityIdentifier("Settings.Roots.AddFolder")

                Spacer()
            }

            if let message = inlineError {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("Settings.Roots.InlineError")
                    .transition(.opacity)
                    .id(errorTick)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: inlineError)
    }

    @ViewBuilder
    private func statusBadge(for row: SettingsRootsModel.RootRow) -> some View {
        switch row.status {
        case .found:
            Label("Found", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
                .accessibilityIdentifier("Settings.Roots.Status.Found.\(row.path)")
        case .missing:
            Label("Missing", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .labelStyle(.titleAndIcon)
                .help("This path no longer exists. Remove it or restore the folder.")
                .accessibilityIdentifier("Settings.Roots.Status.Missing.\(row.path)")
        }
    }

    // MARK: - Logic helpers

    /// Rows computed from the current persistence state. Indirection through
    /// the optional model keeps `@Environment` access safe during first-run
    /// body evaluation (the model is created in `.onAppear`).
    private var effectiveRows: [SettingsRootsModel.RootRow] {
        rootsModel?.rows ?? fallbackRows
    }

    /// Produce a synchronous-safe fallback row list by constructing a
    /// throwaway model. Used only during the very first body evaluation on
    /// the initial render.
    private var fallbackRows: [SettingsRootsModel.RootRow] {
        SettingsRootsModel(persistence: persistence).rows
    }

    private func handleAddFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Folder"
        panel.title = "Choose a folder to scan for git repositories"

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        let model = rootsModel ?? SettingsRootsModel(persistence: persistence)
        rootsModel = model
        let ok = model.addRoot(path: url.path)
        if ok {
            inlineError = nil
            Task { await sidebarModel.refresh() }
        } else {
            showInlineError(model.inlineError ?? "Couldn't add folder.")
        }
    }

    private func handleRemove(row: SettingsRootsModel.RootRow) {
        guard !row.isDefault else { return }
        let model = rootsModel ?? SettingsRootsModel(persistence: persistence)
        rootsModel = model
        if model.removeRoot(path: row.path) {
            Task { await sidebarModel.refresh() }
        }
    }

    private func showInlineError(_ message: String) {
        inlineError = message
        errorTick &+= 1
        let currentTick = errorTick
        // Auto-dismiss after ~5s. Later errors supersede earlier ones via the
        // tick counter so only the latest fade-out actually clears the state.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if currentTick == errorTick {
                inlineError = nil
            }
        }
    }
}
