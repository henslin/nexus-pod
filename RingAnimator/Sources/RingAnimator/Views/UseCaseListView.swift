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
    /// Passed in because this same list is also every user-made section —
    /// see `UserSectionStore` — and each one names itself.
    var title: String = "Use Cases"

    @State private var showingNewDialog = false
    @State private var newUseCaseName = ""

    @State private var renamingUseCase: RingPreset?
    @State private var renameText = ""

    @State private var importErrorMessage: String?
    @State private var importSuccessMessage: String?

    var body: some View {
        ListColumn(title: title, subtitle: subtitle) {
            List(selection: $selectedUseCaseID) {
                Section {
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
                        // The list's order *is* the store's array order, so
                        // a move is just a move.
                        .onMove { store.move(fromOffsets: $0, toOffset: $1) }
                    }
                }
            }
            .listStyle(.sidebar)
        } actions: {
            importBlenderButton
            Button {
                newUseCaseName = "Use Case \(store.presets.count + 1)"
                showingNewDialog = true
            } label: {
                Label("New Use Case", systemImage: "plus")
            }
            .help("Create a new use-case animation, with its own full set of controls")
        // Its own button rather than a third item inside the Share
        // menu below. Taking delivery of a pattern library is the way
        // most of this list gets populated, and it was sitting behind
        // an upload-looking icon in a menu of JSON import/export —
        // findable only if you already knew it was there.
            Button {
                importPatternFolder()
            } label: {
                Label("Import Patterns", systemImage: "tray.and.arrow.down")
            }
            .help("Import a folder of firmware pattern scripts (.py) — one use case per pattern")
            Menu {
                Button("Export Library…") { exportLibrary() }
                    .disabled(store.presets.isEmpty)
                Button("Import…") { importUseCases() }
                Divider()
                Button("Import Pattern Scripts…") { importPatternFolder() }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up.on.square")
            }
            .help("Export use cases to share with your team, or import ones they've sent you")
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

    private var subtitle: String {
        let count = store.presets.count
        guard count > 0 else { return "No animations yet" }
        return count == 1 ? "1 animation" : "\(count) animations"
    }

    /// Reads a Blender script into whichever use case is selected.
    ///
    /// Lives here rather than in the detail view's controls panel because
    /// it isn't about the parameters on the right — it replaces most of
    /// them. Posted as a notification because the config it writes into is
    /// `UseCaseDetailView`'s own `@StateObject`, which this column has no
    /// reference to; only the selected use case's detail view is mounted,
    /// so exactly one listener answers.
    private var importBlenderButton: some View {
        Button {
            NotificationCenter.default.post(name: .importBlenderIntoUseCase, object: nil)
        } label: {
            Label("Import Blender…", systemImage: "curlybraces")
        }
        // Icon-only, like its neighbours — see `ListColumn.actionBar`. The
        // label survives as the tooltip and the accessibility name.
        .disabled(selectedUseCaseID == nil)
        .help("Read a Blender LED-ring script into the selected use case")
    }

    // MARK: - Bulk pattern import

    /// Imports a whole firmware pattern library at once — one use case per
    /// script file. The reading, replacing and reporting all live in
    /// `PatternFolderImport`; this is just the panel in front of it.
    private func importPatternFolder() {
        let panel = NSOpenPanel()
        // Both, and several of each. A library turns up as a folder, but
        // "re-import just these three" is the more common follow-up, and
        // an open panel that only takes folders makes that a folder's
        // worth of work.
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

        let result = PatternFolderImport.run(files, into: store)
        guard result.imported > 0 else {
            importErrorMessage = "Nothing in there read as a firmware pattern."
            return
        }
        importSuccessMessage = PatternFolderImport.summary(result)
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
            Button("Rename…", action: onRename)
            Button("Export…", action: onExport)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
