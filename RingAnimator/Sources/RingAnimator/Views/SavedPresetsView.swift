import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RingAnimatorCore

/// The "Saved Animations" column — a scrolling list of `RingConfig`
/// snapshots you've bookmarked, living alongside `ControlsView` inside the
/// Nexus section (see `ContentView`, which puts the two in an
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
    /// The Nexus timeline, owned by `ContentView`. Needed here because a
    /// multi-phase pattern imports as steps, not as a single config.
    @ObservedObject var timelinePlayer: TimelinePlayer
    /// The Use Cases store, only so a pattern *library* can be imported
    /// from here as well.
    ///
    /// A folder import has to create something per file, and Nexus's own
    /// saved animations can't hold what these files carry: a saved
    /// animation is a bookmark of `config` alone, while the Nexus timeline
    /// is one shared document — so the twenty-one multi-phase patterns
    /// would land here with their steps silently dropped. Use cases each
    /// own a timeline keyed by their id, so that's where a library can
    /// arrive intact. The menu item says so rather than quietly sending
    /// the result somewhere else.
    @ObservedObject var useCaseStore: RingPresetStore

    @State private var selectedPresetID: RingPreset.ID?

    @State private var showingSaveDialog = false
    /// Non-nil while the Blender import report is up. A struct rather than a
    /// pair of booleans so the sheet can't be presented without a result to
    /// show.
    @State private var blenderReport: BlenderReport?
    @State private var newPresetName = ""

    @State private var renamingPreset: RingPreset?
    @State private var renameText = ""

    @State private var importErrorMessage: String?
    @State private var importSuccessMessage: String?

    var body: some View {
        ListColumn(title: "Nexus", subtitle: subtitle) {
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
                        // The list's order *is* the store's array order, so
                        // a move is just a move.
                        .onMove { store.move(fromOffsets: $0, toOffset: $1) }
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selectedPresetID) { _, newValue in
                guard let id = newValue, let preset = store.presets.first(where: { $0.id == id }) else { return }
                preset.apply(to: config)
            }
        } actions: {
            Button {
                newPresetName = "Animation \(store.presets.count + 1)"
                showingSaveDialog = true
            } label: {
                Label("Save Current Animation", systemImage: "plus")
            }
            .help("Save the ring's current settings as a new saved animation")
            Menu {
                Button("Export Library…") { exportLibrary() }
                    .disabled(store.presets.isEmpty)
                Button("Import…") { importPresets() }
                Divider()
                Button("Import Blender Script…") { importBlenderScript() }
                Button("Import Pattern Library → Use Cases…") { importPatternFolder() }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up.on.square")
            }
            .help("Export saved animations to share with your team, or import ones they've sent you")
        }
        // Custom sheets instead of `.alert(...)` with an embedded
        // `TextField` — SwiftUI alerts only support a bare TextField with
        // no room for a companion control, and typing doesn't reach any
        // TextField in this app right now (see `PasteableTextField`'s doc
        // comment), so the alert version was simply unusable: nothing you
        // typed ever landed in the field. A plain sheet gives room for the
        // paste-workaround button alongside it.
        .sheet(isPresented: $showingSaveDialog) { saveDialog }
        .sheet(item: $blenderReport) { report in
            BlenderImportReportView(fileName: report.fileName, outcome: report.outcome) {
                blenderReport = nil
            }
        }
        .sheet(item: $renamingPreset) { _ in renameDialog }
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

    // MARK: - Save / Rename dialogs

    private var saveDialog: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Animation").font(.headline)
            PasteableTextField("Name", text: $newPresetName) { confirmSave() }
            HStack {
                Spacer()
                Button("Cancel") { showingSaveDialog = false }
                    .ringGlassButtonStyle()
                Button("Save") { confirmSave() }
                    .keyboardShortcut(.defaultAction)
                    .ringGlassButtonStyle()
            }
        }
        .padding()
        .frame(width: 320)
    }

    private func confirmSave() {
        let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        store.add(RingPreset(name: name.isEmpty ? "Untitled" : name, config: config))
        showingSaveDialog = false
    }

    private var renameDialog: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Animation").font(.headline)
            PasteableTextField("Name", text: $renameText) { confirmRename() }
            HStack {
                Spacer()
                Button("Cancel") { renamingPreset = nil }
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
        if let preset = renamingPreset {
            store.rename(preset.id, to: renameText)
        }
        renamingPreset = nil
    }

    // MARK: - Export / Import

    /// What the section is *for*, then how much is in it — Mail's
    /// "All Mail · 628,761 messages" shape. A count on its own doesn't say
    /// why you'd come here, and the purpose on its own goes stale the
    /// moment you want to know whether you've saved anything.
    private var subtitle: String {
        let count = store.presets.count
        let purpose = "Discovery design for the agentic tab"
        guard count > 0 else { return purpose }
        return count == 1 ? "\(purpose) · 1 saved" : "\(purpose) · \(count) saved"
    }

    private func exportSingle(_ preset: RingPreset) {
        let panel = NSSavePanel()
        let safeName = preset.name.isEmpty ? "animation" : preset.name
        panel.nameFieldStringValue = "\(safeName).json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            try? store.exportPresetJSON(preset).write(to: url)
        }
    }


    /// Opens a foreign Blender ring script and interprets it into `config`.
    ///
    /// Separate from the preset Import above, which reads this app's own
    /// JSON. This one takes someone else's `.py` — see
    /// `BlenderScriptImporter` for why it's an interpretation rather than a
    /// translation, and why the report is always shown.
    private func importBlenderScript() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "py") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a Blender LED-ring script (.py)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let (text, delegatedTo) = BlenderScriptImporter.readScriptFollowingDelegation(at: url) else {
            blenderReport = BlenderReport(url.lastPathComponent, BlenderScriptImporter.Outcome(
                applied: [],
                dropped: [],
                caveat: "Couldn't read this file as text — it isn't UTF-8, Latin-1, Mac Roman or UTF-16. Nothing was changed."
            ))
            return
        }

        // This app's own export round-trips exactly, so try that first and
        // only fall back to interpreting a foreign script.
        if case .success = CodeGenerators.applyBlenderCode(text, to: config) {
            blenderReport = BlenderReport(url.lastPathComponent, BlenderScriptImporter.Outcome(
                applied: ["Read this app's own NEXUS_PARAMS block — an exact round-trip, not an interpretation."],
                dropped: [],
                caveat: nil
            ))
            return
        }
        let hadSteps = !timelinePlayer.timeline.segments.isEmpty
        var outcome = BlenderScriptImporter.apply(text, to: config)
        // Say so when the chosen file only hands off to another one, rather
        // than silently reporting a pattern the user didn't pick.
        if let delegatedTo, !outcome.applied.isEmpty {
            outcome.applied.insert(
                "This pattern hands off to \(delegatedTo) — imported from there",
                at: 0
            )
        }
        // See `UseCaseDetailView.importBlenderScript` — a multi-phase
        // pattern becomes timeline steps rather than collapsing into one
        // config.
        if !outcome.applied.isEmpty {
            // Always install, phases or not — an empty timeline clears any
            // steps left from a previous import so the strip and the ring
            // agree on which pattern is loaded.
            timelinePlayer.installImported(outcome.timeline ?? RingTimeline())
            if outcome.timeline == nil, hadSteps {
                outcome.applied.append("Single looping behavior → cleared the previous pattern's timeline steps")
            }
        }
        blenderReport = BlenderReport(url.lastPathComponent, outcome)
    }

    /// The same importer the Use Cases toolbar runs — see
    /// `useCaseStore` above for why the result lands there rather than in
    /// this list.
    private func importPatternFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType(filenameExtension: "py") ?? .plainText]
        panel.message = "Choose a folder of firmware pattern scripts, or the scripts themselves"
        panel.prompt = "Import"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        let files = PatternFolderImport.scriptURLs(in: panel.urls)
        guard !files.isEmpty else {
            importErrorMessage = "No .py files in there."
            return
        }
        let result = PatternFolderImport.run(files, into: useCaseStore)
        guard result.imported > 0 else {
            importErrorMessage = "Nothing in there read as a firmware pattern."
            return
        }
        importSuccessMessage = PatternFolderImport.summary(result)
            + "\n\nThey're in the Use Cases tab."
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
            importErrorMessage = "That file isn't a saved animation or animation library exported from Nexus."
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
            RingView(config: previewConfig, diameter: 22, frameRate: RingView.thumbnailFrameRate)
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


/// One Blender import's result, wrapped for `sheet(item:)`.
struct BlenderReport: Identifiable {
    let id = UUID()
    let fileName: String
    let outcome: BlenderScriptImporter.Outcome

    init(_ fileName: String, _ outcome: BlenderScriptImporter.Outcome) {
        self.fileName = fileName
        self.outcome = outcome
    }
}
