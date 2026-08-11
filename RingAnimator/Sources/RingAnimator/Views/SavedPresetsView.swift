import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RingAnimatorCore

/// The "Saved Animations" column — a scrolling list of `RingConfig`
/// snapshots you've bookmarked, living alongside `ControlsView` inside the
/// Ring Designer section (see `ContentView`, which puts the two in an
/// `HSplitView` together). Modeled on `CueListView`'s list-column pattern;
/// export/import uses the same `NSSavePanel`/`NSOpenPanel` convention as
/// `ExportView`/`CueListView` — the app doesn't have a macOS share sheet
/// anywhere, so a saved `.json` file you send over Slack/AirDrop/email,
/// which a teammate loads back in via Import…, is the established way to
/// hand something off.
///
/// Clicking a row loads it straight into the ring you're looking at
/// (`config`, shared with `ControlsView`/`PreviewTab`) — there's no separate
/// "Load" step.
struct SavedPresetsView: View {
    @ObservedObject var store: RingPresetStore
    @ObservedObject var config: RingConfig

    @State private var selectedPresetID: RingPreset.ID?

    @State private var showingSaveDialog = false
    @State private var newPresetName = ""

    @State private var renamingPreset: RingPreset?
    @State private var renameText = ""

    @State private var importErrorMessage: String?
    @State private var importSuccessMessage: String?

    var body: some View {
        List(selection: $selectedPresetID) {
            Section("Saved Animations") {
                if store.presets.isEmpty {
                    Text("Click + to save the animation you're looking at now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(store.presets) { preset in
                        SavedAnimationRow(
                            preset: preset,
                            onLoad: { preset.apply(to: config) },
                            onRename: {
                                renameText = preset.name
                                renamingPreset = preset
                            },
                            onExport: { exportSingle(preset) },
                            onDelete: { store.delete(preset.id) }
                        )
                        .tag(preset.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: selectedPresetID) { _, newValue in
            guard let id = newValue, let preset = store.presets.first(where: { $0.id == id }) else { return }
            preset.apply(to: config)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    newPresetName = "Animation \(store.presets.count + 1)"
                    showingSaveDialog = true
                } label: {
                    Label("Save Current Animation", systemImage: "plus")
                }
                .help("Save the ring's current settings as a new saved animation")
            }
            ToolbarItem {
                Menu {
                    Button("Export Library…") { exportLibrary() }
                        .disabled(store.presets.isEmpty)
                    Button("Import…") { importPresets() }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up.on.square")
                }
                .help("Export saved animations to share with your team, or import ones they've sent you")
            }
        }
        .alert("Save Animation", isPresented: $showingSaveDialog) {
            TextField("Name", text: $newPresetName)
            Button("Save") {
                let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
                store.add(RingPreset(name: name.isEmpty ? "Untitled" : name, config: config))
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Rename Animation",
            isPresented: Binding(get: { renamingPreset != nil }, set: { if !$0 { renamingPreset = nil } })
        ) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let preset = renamingPreset {
                    store.rename(preset.id, to: renameText)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Couldn't Import",
            isPresented: Binding(get: { importErrorMessage != nil }, set: { if !$0 { importErrorMessage = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(importErrorMessage ?? "")
        }
        .alert(
            "Imported",
            isPresented: Binding(get: { importSuccessMessage != nil }, set: { if !$0 { importSuccessMessage = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(importSuccessMessage ?? "")
        }
    }

    // MARK: - Export / Import

    private func exportSingle(_ preset: RingPreset) {
        let panel = NSSavePanel()
        let safeName = preset.name.isEmpty ? "animation" : preset.name
        panel.nameFieldStringValue = "\(safeName).json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            try? store.exportPresetJSON(preset).write(to: url)
        }
    }

    private func exportLibrary() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ring-pod-animations.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            try? store.exportLibraryJSON().write(to: url)
        }
    }

    private func importPresets() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else {
            importErrorMessage = "Couldn't read that file."
            return
        }
        switch store.importJSON(data) {
        case .success(let count):
            importSuccessMessage = count == 1
                ? "Added 1 saved animation."
                : "Added \(count) saved animations."
        case .failure:
            importErrorMessage = "That file isn't a saved animation or animation library exported from Ring Pod."
        }
    }
}

/// One row in the Saved Animations list — shows a real, live-animating
/// miniature of the saved animation instead of a static color swatch,
/// which is what actually answers "which saved animation is which" at a
/// glance (an exported `.gif` would need frame-capture + GIF-encoding
/// machinery for no real benefit here, since nothing needs to leave the
/// app — the live ring already *is* the accurate, always-in-sync
/// thumbnail).
private struct SavedAnimationRow: View {
    let preset: RingPreset
    let onLoad: () -> Void
    let onRename: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void

    /// A throwaway `RingConfig`, created once and kept for this row's
    /// lifetime rather than rebuilt every render — `RingConfig.init()` does
    /// a synchronous Keychain read and spins up a `VoiceConversationController`,
    /// both wasted work if repeated unnecessarily. Same reasoning
    /// `LEDCuePreviewView.animationConfig` already uses for its own live
    /// mini `RingView` preview. `preset.apply(to:)` copies this preset's
    /// saved settings into it on `.onAppear` and whenever the preset itself
    /// changes (e.g. after a rename), rather than needing this row to
    /// duplicate `RingPreset.apply(to:)`'s field-by-field copy.
    @StateObject private var previewConfig = RingConfig()

    var body: some View {
        HStack(spacing: 10) {
            RingView(config: previewConfig, diameter: 22)
                .frame(width: 28, height: 28)
                .onAppear { preset.apply(to: previewConfig) }
                .onChange(of: preset) { _, newValue in newValue.apply(to: previewConfig) }
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(preset.animationType.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contextMenu {
            Button("Load", action: onLoad)
            Button("Rename…", action: onRename)
            Button("Export…", action: onExport)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
