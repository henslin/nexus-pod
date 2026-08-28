import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RingAnimatorCore

/// The "Use Cases" column — a flat list of team-created, fully independent
/// named animations (see `UseCaseDetailView`), each with its own complete
/// set of controls rather than sharing Nexus's live `RingConfig`. Modeled
/// directly on `SavedPresetsView`'s list column (same toolbar/dialog/
/// export-import conventions), but backed by a *second*, independent
/// `RingPresetStore` instance (see `ContentView`) — clicking a row selects
/// it for editing in `UseCaseDetailView`, rather than loading it into
/// Nexus's shared ring the way a saved animation does.
struct UseCaseListView: View {
    @ObservedObject var store: RingPresetStore
    @Binding var selectedUseCaseID: RingPreset.ID?

    @State private var showingNewDialog = false
    @State private var newUseCaseName = ""

    @State private var renamingUseCase: RingPreset?
    @State private var renameText = ""

    @State private var importErrorMessage: String?
    @State private var importSuccessMessage: String?

    var body: some View {
        List(selection: $selectedUseCaseID) {
            Section("Use Cases") {
                if store.presets.isEmpty {
                    Text("Click + to create a new use-case animation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(store.presets) { preset in
                        UseCaseRow(
                            preset: preset,
                            onRename: {
                                renameText = preset.name
                                renamingUseCase = preset
                            },
                            onExport: { exportSingle(preset) },
                            onDelete: {
                                store.delete(preset.id)
                                // A use case's timeline lives in its own
                                // store file (see
                                // `TimelinePlayer.useCaseFileName`), which
                                // nothing else would ever clean up — a
                                // deleted use case would otherwise leave an
                                // orphan in Application Support forever,
                                // and a new use case can't collide with it
                                // since the name is keyed by UUID.
                                TimelinePlayer.deleteStore(
                                    fileName: TimelinePlayer.useCaseFileName(preset.id)
                                )
                                if selectedUseCaseID == preset.id { selectedUseCaseID = nil }
                            }
                        )
                        .tag(preset.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem {
                Button {
                    newUseCaseName = "Use Case \(store.presets.count + 1)"
                    showingNewDialog = true
                } label: {
                    Label("New Use Case", systemImage: "plus")
                }
                .help("Create a new use-case animation, with its own full set of controls")
            }
            ToolbarItem {
                Menu {
                    Button("Export Library…") { exportLibrary() }
                        .disabled(store.presets.isEmpty)
                    Button("Import…") { importUseCases() }
                    Divider()
                    Button("Import Pattern Folder…") { importPatternFolder() }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up.on.square")
                }
                .help("Export use cases to share with your team, or import ones they've sent you")
            }
        }
        .sheet(isPresented: $showingNewDialog) { newDialog }
        .sheet(item: $renamingUseCase) { _ in renameDialog }
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

    // MARK: - Bulk pattern import

    /// Imports a whole firmware pattern library at once — one use case per
    /// `.py` file, each with its palette, timings and phase steps.
    ///
    /// The single-file button in `UseCaseDetailView` imports *into* the use
    /// case you're editing, which is the right shape for reworking one
    /// animation and the wrong shape for taking delivery of sixty-nine.
    /// This creates them instead.
    ///
    /// Everything goes through `BlenderScriptImporter.apply`, so a bulk
    /// import and a single import cannot drift: same reading, same recorded
    /// streams, same phase timelines. Files that aren't patterns —
    /// `pattern_common.py`, the registry, `__init__.py` — apply nothing and
    /// are skipped rather than becoming empty use cases.
    private func importPatternFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder of firmware pattern scripts (.py)"
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let files: [URL]
        do {
            files = try FileManager.default
                .contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "py" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            importErrorMessage = "Couldn't read that folder: \(error.localizedDescription)"
            return
        }

        guard !files.isEmpty else {
            importErrorMessage = "No .py files in that folder."
            return
        }

        var imported = 0
        var exact = 0
        var phased = 0
        var skipped: [String] = []

        for file in files {
            guard let (text, _) = BlenderScriptImporter.readScriptFollowingDelegation(at: file) else {
                skipped.append(file.lastPathComponent)
                continue
            }
            let config = RingConfig()
            let outcome = BlenderScriptImporter.apply(text, to: config)
            guard !outcome.applied.isEmpty else {
                skipped.append(file.lastPathComponent)
                continue
            }

            let name = displayName(for: file)
            let preset = store.add(RingPreset(name: name, config: config))
            imported += 1
            if config.firmwarePatternStream != nil { exact += 1 }

            // A use case's timeline lives in its own store file keyed by the
            // preset's UUID, so writing it means standing up that use case's
            // player and installing into it — the same path the detail view
            // uses when you import into an open use case.
            if let timeline = outcome.timeline {
                let player = TimelinePlayer(
                    fileName: TimelinePlayer.useCaseFileName(preset.id)
                )
                player.installImported(timeline)
                phased += 1
            }
        }

        guard imported > 0 else {
            importErrorMessage = "Nothing in that folder read as a firmware pattern."
            return
        }

        var summary = "Added \(imported) use case\(imported == 1 ? "" : "s")."
        if exact > 0 {
            summary += " \(exact) replay the device's own command stream exactly."
        }
        if phased > 0 {
            summary += " \(phased) came in as multi-step timelines."
        }
        if !skipped.isEmpty {
            // Named rather than counted: the skips are usually the library
            // and the registry, and saying which ones they were is the
            // difference between "as expected" and "something went wrong".
            summary += "\n\nSkipped \(skipped.count) file\(skipped.count == 1 ? "" : "s") that aren't patterns: \(skipped.joined(separator: ", "))"
        }
        importSuccessMessage = summary
    }

    /// `warble_kaleidoscope_blue.py` → "Warble Kaleidoscope Blue".
    private func displayName(for file: URL) -> String {
        file.deletingPathExtension().lastPathComponent
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    // MARK: - New / Rename dialogs

    private var newDialog: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Use Case").font(.headline)
            PasteableTextField("Name", text: $newUseCaseName) { confirmNew() }
            HStack {
                Spacer()
                Button("Cancel") { showingNewDialog = false }
                    .ringGlassButtonStyle()
                Button("Create") { confirmNew() }
                    .keyboardShortcut(.defaultAction)
                    .ringGlassButtonStyle()
            }
        }
        .padding()
        .frame(width: 320)
    }

    private func confirmNew() {
        let name = newUseCaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        // Starts from a fresh, default `RingConfig` — unlike Nexus's own
        // "+" button (which bookmarks whatever's *currently* on screen),
        // there's no single shared ring state a new use case could start
        // from, so it opens ready to be tuned from scratch in
        // `UseCaseDetailView`.
        let preset = store.add(RingPreset(name: name.isEmpty ? "Untitled" : name, config: RingConfig()))
        selectedUseCaseID = preset.id
        showingNewDialog = false
    }

    private var renameDialog: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Use Case").font(.headline)
            PasteableTextField("Name", text: $renameText) { confirmRename() }
            HStack {
                Spacer()
                Button("Cancel") { renamingUseCase = nil }
                    .ringGlassButtonStyle()
                Button("Save") { confirmRename() }
                    .keyboardShortcut(.defaultAction)
                    .ringGlassButtonStyle()
            }
        }
        .padding()
        .frame(width: 320)
    }

    private func confirmRename() {
        if let preset = renamingUseCase {
            store.rename(preset.id, to: renameText)
        }
        renamingUseCase = nil
    }

    // MARK: - Export / Import

    private func exportSingle(_ preset: RingPreset) {
        let panel = NSSavePanel()
        let safeName = preset.name.isEmpty ? "use-case" : preset.name
        panel.nameFieldStringValue = "\(safeName).json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            try? store.exportPresetJSON(preset).write(to: url)
        }
    }

    private func exportLibrary() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "use-cases.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            try? store.exportLibraryJSON().write(to: url)
        }
    }

    private func importUseCases() {
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
                ? "Added 1 use case."
                : "Added \(count) use cases."
        case .failure:
            importErrorMessage = "That file isn't a use case or use-case library exported from Nexus."
        }
    }
}

/// One row — a live, always-in-sync miniature of the use case's animation,
/// same reasoning as `SavedPresetsView`'s `SavedAnimationRow`.
private struct UseCaseRow: View {
    let preset: RingPreset
    let onRename: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void

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
            Button("Rename…", action: onRename)
            Button("Export…", action: onExport)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
