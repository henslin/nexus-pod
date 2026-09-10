import SwiftUI
import RingAnimatorCore

/// Top-level layout: one native three-column split (sidebar → content →
/// detail), the same structural pattern Mail/Notes/Xcode use. The sidebar
/// picks which tool you're in; the content and detail columns swap based on
/// that choice. This replaces an earlier version that stacked two SwiftUI
/// `TabView`s directly on top of each other (an outer Nexus/Cue
/// Library tab strip, with a second Preview/Export strip immediately below
/// it) — visually cramped and not a standard macOS pattern. A single sidebar
/// plus a toolbar-based segmented control for Nexus's
/// Preview/Export toggle reads as one coherent window instead of two
/// stacked widgets.
struct ContentView: View {
    @StateObject private var config = RingConfig()
    @StateObject private var cueStore = LEDCueStore()
    @StateObject private var presetStore = RingPresetStore()
    /// A second, independent `RingPresetStore` — same shape of data (a
    /// named, fully-tunable `RingPreset`) as Nexus's own Saved Animations,
    /// just its own JSON file (`use-cases.json`) so the two lists never
    /// intermix. See `UseCaseListView`/`UseCaseDetailView`.
    @StateObject private var useCaseStore = RingPresetStore(fileName: "use-cases.json")
    /// Non-nil only when a launch's library sync actually moved something,
    /// which is what puts the summary on screen.
    @State private var librarySync: UseCaseLibrary.Outcome?
    /// The sequencing document — see `TimelinePlayer`. Bound to `config`
    /// in `.onAppear` below, which is what makes the Controls panel edit
    /// the selected step in place rather than a detached scratch copy.
    /// The sequence for whichever saved animation is selected in Nexus —
    /// or the scratch one when nothing is. See `TimelinePlayers`.
    @StateObject private var timelinePlayers = TimelinePlayers()
    /// The app's undo manager — see `RingPodApp`, which owns it and puts
    /// Undo/Redo in the Edit menu.
    let undoManager: UndoManager

    /// Nexus's selected saved animation. Hoisted out of `SavedPresetsView`
    /// because the timeline is keyed by it, and only `ContentView` can own
    /// something both columns and the detail pane need.
    @State private var selectedPresetID: RingPreset.ID?
    /// The section a Delete click is asking about.
    ///
    /// Deleting a section takes every animation in it and every sequence
    /// those animations own — by some distance the most destructive thing
    /// in the app — and it used to happen on one click of a context menu.
    /// Meanwhile Apply to All, which only changes settings, has always
    /// asked first. The confirmation belonged here more than there.
    @State private var deletingSection: UserSection?
    /// The stage's own state — zoom, pan, appearance, where Large Preview is
    /// parked. Owned here, one instance, and handed to whichever section is
    /// showing, so switching sections doesn't reset the canvas. See
    /// `StageState`.
    @StateObject private var stageState = StageState()

    @State private var section: AppSection? = .ringDesigner
    @State private var designerTab: DetailTab = .preview
    @State private var cueTab: DetailTab = .preview
    @State private var useCaseTab: DetailTab = .preview
    @State private var selectedCueID: String? = LEDCueLibrary.all.first?.id
    @State private var cueSearchText: String = ""
    @State private var selectedUseCaseID: RingPreset.ID?
    /// Sections someone made — see `UserSectionStore`.
    @StateObject private var userSections = UserSectionStore()
    @State private var showingNewSection = false
    @State private var newSectionName = ""
    @State private var renamingSection: UserSection?
    @State private var renameSectionText = ""
    /// Which preset is selected *within* each user section, kept per
    /// section so switching between two doesn't clear the other's.
    @State private var userSelection: [UUID: RingPreset.ID] = [:]
    @StateObject private var sectionStores = SectionStores()
    /// The post-update release notes — see `WhatsNewPresenter` for when
    /// they're due. Also reachable on demand from the Help menu, which is
    /// where macOS users look for "what changed".
    @State private var showingWhatsNew = false

    /// What the sidebar can be pointed at: one of the three built-in
    /// sections, or a section someone made.
    enum AppSection: Identifiable, Hashable {
        case ringDesigner
        case cueLibrary
        case useCases
        case user(UUID)

        static let fixed: [AppSection] = [.ringDesigner, .cueLibrary, .useCases]

        var id: String {
            switch self {
            case .ringDesigner: return "nexus"
            case .cueLibrary: return "cues"
            case .useCases: return "useCases"
            case .user(let id): return id.uuidString
            }
        }

        var title: String {
            switch self {
            case .ringDesigner: return "Nexus"
            case .cueLibrary: return "Cue Library"
            case .useCases: return "Use Cases"
            // A user section's name lives in the store, not in the case —
            // it can be renamed, and duplicating it here would be a second
            // copy to keep in step.
            case .user: return ""
            }
        }

        var icon: String {
            switch self {
            case .ringDesigner: return "sparkles"
            case .cueLibrary: return "books.vertical"
            case .useCases: return "target"
            case .user: return "folder"
            }
        }

        var userID: UUID? {
            if case .user(let id) = self { return id }
            return nil
        }
    }


    var body: some View {
        NavigationSplitView {
            // A plain `ForEach` here (rather than the `List(data:selection:
            // content:)` shorthand) so a `Divider()` can sit between Cue
            // Library and Use Cases — visually groups them apart from
            // Nexus without needing a full `Section` header for just two
            // items.
            VStack(spacing: 0) {
                List(selection: $section) {
                    ForEach(AppSection.fixed) { item in
                        Label(item.title, systemImage: item.icon).tag(item)
                        if item == .cueLibrary {
                            Divider()
                        }
                    }
                    if !userSections.sections.isEmpty {
                        Section("Sections") {
                            ForEach(userSections.sections) { userSection in
                                Label(userSection.name, systemImage: "folder")
                                    .tag(AppSection.user(userSection.id))
                                    .contextMenu {
                                        Button("Rename…") {
                                            renamingSection = userSection
                                            renameSectionText = userSection.name
                                        }
                                        Button("Delete", role: .destructive) {
                                            deletingSection = userSection
                                        }
                                    }
                            }
                            .onMove { userSections.move(fromOffsets: $0, toOffset: $1) }
                        }
                    }
                }
                Divider()
                // Just "+". A label would have to name what it makes, and
                // "New Section" is the only honest name — these aren't
                // folders, they don't contain the built-in sections, and
                // each one is its own list with its own storage.
                HStack {
                    Button {
                        newSectionName = "Section \(userSections.sections.count + 1)"
                        showingNewSection = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("New section — its own list of animations")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
            .navigationSplitViewColumnWidth(180)
        } content: {
            switch section {
            case .ringDesigner:
                SavedPresetsView(
                    store: presetStore,
                    config: config,
                    timelinePlayer: timelinePlayer,
                    useCaseStore: useCaseStore,
                    selectedPresetID: $selectedPresetID
                )
                    .listColumnWidth()
            case .cueLibrary:
                CueListView(store: cueStore, selectedCueID: $selectedCueID, searchText: $cueSearchText)
                    .listColumnWidth()
            case .useCases:
                UseCaseListView(
                    store: useCaseStore,
                    selectedUseCaseID: $selectedUseCaseID,
                    nexusTimeline: timelinePlayer
                )
                    .listColumnWidth()
            case .user(let id):
                // The same list as Use Cases, over that section's own
                // store. `.id(id)` so switching sections rebuilds it
                // against the new store rather than keeping the old one.
                UseCaseListView(
                    store: store(forSection: id),
                    selectedUseCaseID: binding(forSection: id),
                    nexusTimeline: timelinePlayer
                )
                .id(id)
                .listColumnWidth()
            case .none:
                ContentUnavailableView("Select a tool", systemImage: "sidebar.left")
            }
        } detail: {
            switch section {
            case .ringDesigner:
                // Preview/Export in the middle, Controls pinned to the far
                // right edge — the Figma/Sketch inspector-panel convention
                // (layers left, canvas center, properties right) rather
                // than sitting Controls right next to the Saved Animations
                // list. `designerDetail` keeps its own toolbar-hosted
                // Preview/Export segmented control regardless of where it
                // sits in this split.
                HSplitView {
                    designerDetail
                        .frame(minWidth: 420, idealWidth: 640)
                    ControlsView(config: config)
                        .frame(minWidth: 260, idealWidth: 300, maxWidth: 340)
                }
            case .cueLibrary:
                cueDetail
            case .useCases:
                useCaseDetail
            case .user(let id):
                userSectionDetail(id)
            case .none:
                EmptyView()
            }
        }
        // macOS reserves a band above the content column and renders these
        // into it, at its own size. Leaving them off doesn't leave it empty
        // — the window falls back to the app's own name, which every
        // section shares and so says nothing; a hand-drawn heading further
        // down the column left that band empty and said the name twice.
        // The section, and what the section is for.
        .navigationTitle(sectionTitle)
        // Not `.navigationSubtitle`: it's system-drawn on a single line and
        // can only truncate, so the longest description ran off the edge of
        // the column. `ListColumn` draws it instead, where it wraps.
        .environment(\.columnSubtitle, sectionSubtitle)
        .sheet(isPresented: $showingWhatsNew) {
            WhatsNewView {
                WhatsNewPresenter.markSeen()
                showingWhatsNew = false
            }
        }
        .sheet(isPresented: $showingNewSection) {
            SectionNameSheet(title: "New Section", name: $newSectionName) {
                let made = userSections.add(named: newSectionName)
                section = .user(made.id)
                showingNewSection = false
            } onCancel: {
                showingNewSection = false
            }
        }
        .sheet(item: $renamingSection) { target in
            SectionNameSheet(title: "Rename Section", name: $renameSectionText) {
                userSections.rename(target.id, to: renameSectionText)
                renamingSection = nil
            } onCancel: {
                renamingSection = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showWhatsNew)) { _ in
            showingWhatsNew = true
        }
        .confirmationDialog(
            deletingSection.map { "Delete “\($0.name)”?" } ?? "",
            isPresented: Binding(
                get: { deletingSection != nil },
                set: { if !$0 { deletingSection = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Section", role: .destructive) {
                if let section = deletingSection { deleteUserSection(section) }
                deletingSection = nil
            }
            Button("Cancel", role: .cancel) { deletingSection = nil }
        } message: {
            Text(deletingSection.map { sectionDeletionWarning(for: $0) } ?? "")
        }
        .onAppear {
            showingWhatsNew = WhatsNewPresenter.shouldPresent()
            // Deferred to `.onAppear` rather than done in an initializer:
            // `@StateObject`s aren't guaranteed to be constructed until the
            // view first appears, and binding needs both objects to exist.
            timelinePlayer.bind(to: config)
            timelinePlayer.undoManager = undoManager
            // Reconcile the use cases with whatever library this build
            // ships — see `UseCaseLibrary.sync` for what it will and won't
            // overwrite. Silent unless something actually moved.
            let outcome = UseCaseLibrary.sync(into: useCaseStore)
            if outcome.changedAnything { librarySync = outcome }
        }
        .onChange(of: selectedPresetID) { _, _ in
            // Each animation has its own player now, and a player that
            // isn't bound can't load a step into the Controls panel — the
            // strip would move while the ring stayed on the last one.
            timelinePlayer.bind(to: config)
            timelinePlayer.undoManager = undoManager
        }
        .alert(
            "Animation Library Updated",
            isPresented: Binding(
                get: { librarySync != nil },
                set: { if !$0 { librarySync = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(librarySync.map(syncMessage) ?? "")
        }
    }

    /// Says what moved, and — when it applies — that nothing of yours did.
    private func syncMessage(_ outcome: UseCaseLibrary.Outcome) -> String {
        var lines: [String] = []
        if !outcome.added.isEmpty {
            lines.append("\(outcome.added.count) new animation\(outcome.added.count == 1 ? "" : "s") added.")
        }
        if !outcome.updated.isEmpty {
            lines.append("\(outcome.updated.count) updated to the version in this build.")
        }
        if !outcome.keptYours.isEmpty {
            lines.append("\(outcome.keptYours.count) you'd edited \(outcome.keptYours.count == 1 ? "was" : "were") left as \(outcome.keptYours.count == 1 ? "it is" : "they are").")
        }
        return lines.joined(separator: "\n")
    }


    private var sectionTitle: String {
        switch section {
        case .ringDesigner: return "Nexus"
        case .cueLibrary: return "Cue Library"
        case .useCases: return "Use Cases"
        case .user(let id):
            return userSections.sections.first(where: { $0.id == id })?.name ?? "Section"
        case .none: return ""
        }
    }

    /// What the section is *for*, then how much is in it — Mail's
    /// "All Mail · 628,761 messages" shape. A count alone doesn't say why
    /// you'd come here; a purpose alone goes stale the moment you want to
    /// know whether you've saved anything.
    ///
    /// Computed here rather than in each column because the title band
    /// belongs to the window, not to the list — and this is where every
    /// store already is.
    private var sectionSubtitle: String {
        func tally(_ count: Int, _ noun: String) -> String {
            count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
        }
        switch section {
        case .ringDesigner:
            let count = presetStore.presets.count
            let purpose = "Discovery design for the agentic tab"
            return count == 0 ? purpose : "\(purpose) · \(count) saved"
        case .cueLibrary:
            let tweaked = cueStore.overrides.count
            let base = "The hardware spec, cue by cue · \(LEDCueLibrary.all.count)"
            return tweaked == 0 ? base : "\(base) · \(tweaked) tweaked"
        case .useCases:
            let count = useCaseStore.presets.count
            let purpose = "Hardware animations, in app"
            guard count > 0 else { return purpose }
            // The library's own date, not the app version: "is this set
            // current?" is a question about the animations, and whoever
            // asks it has no way to map a build number onto an answer.
            var line = "\(purpose) · \(count)"
            if let cut = UseCaseLibrary.bundled?.generatedAt {
                line += " · updated \(cut.formatted(date: .abbreviated, time: .omitted))"
            }
            return line
        case .user(let id):
            // No purpose line: whoever made it named it, so writing one
            // would be putting words in their mouth.
            return tally(store(forSection: id).presets.count, "animation")
        case .none:
            return ""
        }
    }

    /// One `RingPresetStore` per user section, made on demand and kept for
    /// the window's lifetime. Rebuilding it on every redraw would drop the
    /// list's `@Published` identity and re-read the file each time.
    @MainActor
    /// One `TimelinePlayer` per Nexus animation, made on demand and kept
    /// for the window's lifetime — the same arrangement `SectionStores`
    /// uses, and for the same reason: rebuilding one on every redraw would
    /// re-read its file and drop the strip's selection.
    ///
    /// `nil` is the scratch sequence, which is what the ring has before
    /// anything is saved.
    private final class TimelinePlayers: ObservableObject {
        private var players: [UUID: TimelinePlayer] = [:]
        private let scratch = TimelinePlayer()

        func player(for id: UUID?) -> TimelinePlayer {
            guard let id else { return scratch }
            if let existing = players[id] { return existing }
            let made = TimelinePlayer(fileName: TimelinePlayer.animationFileName(id))
            players[id] = made
            return made
        }

        func forget(_ id: UUID) { players[id] = nil }
    }

    private var timelinePlayer: TimelinePlayer {
        timelinePlayers.player(for: selectedPresetID)
    }

    private final class SectionStores: ObservableObject {
        private var stores: [UUID: RingPresetStore] = [:]

        func store(for section: UserSection) -> RingPresetStore {
            if let existing = stores[section.id] { return existing }
            let made = RingPresetStore(fileName: section.storeFileName)
            stores[section.id] = made
            return made
        }

        func forget(_ id: UUID) { stores[id] = nil }
    }

    private func store(forSection id: UUID) -> RingPresetStore {
        guard let section = userSections.sections.first(where: { $0.id == id }) else {
            // Only reachable for a beat while a section is being deleted.
            return RingPresetStore(fileName: "orphaned-section.json")
        }
        return sectionStores.store(for: section)
    }

    private func binding(forSection id: UUID) -> Binding<RingPreset.ID?> {
        Binding(
            get: { userSelection[id] },
            set: { userSelection[id] = $0 }
        )
    }

    @ViewBuilder
    private func userSectionDetail(_ id: UUID) -> some View {
        let store = store(forSection: id)
        if let presetID = userSelection[id],
           let preset = store.presets.first(where: { $0.id == presetID }) {
            UseCaseDetailView(
                preset: preset,
                store: store,
                tab: $useCaseTab,
                stage: { config, playback, timeline in
                    AnyView(RingStage(
                        config: config, playback: playback, timeline: timeline, state: stageState
                    ))
                },
                code: { config in AnyView(ExportView(config: config)) }
            )
            .id(preset.id)
        } else {
            ContentUnavailableView("Select or create an animation", systemImage: "folder")
        }
    }

    /// Says how much is about to go, by counting it rather than saying
    /// "everything in it" and leaving the reader to guess.
    private func sectionDeletionWarning(for userSection: UserSection) -> String {
        let count = store(forSection: userSection.id).presets.count
        switch count {
        case 0: return "This section is empty. This can't be undone."
        case 1: return "Its one animation goes with it, and its sequence. This can't be undone."
        default: return "All \(count) animations in it go with it, and their sequences. This can't be undone."
        }
    }

    private func deleteUserSection(_ userSection: UserSection) {
        sectionStores.forget(userSection.id)
        userSelection[userSection.id] = nil
        if section == .user(userSection.id) { section = .useCases }
        userSections.delete(userSection.id)
    }

    @ViewBuilder
    private var designerDetail: some View {
        DetailPane(tab: $designerTab) {
            PreviewTab(config: config, player: timelinePlayer, stageState: stageState)
                // Rebuilt when the selected animation changes, so the strip
                // and the player it drives belong to that animation —
                // exactly what `.id(preset.id)` does for a use case.
                .id(selectedPresetID)
        } code: {
            ExportView(config: config)
        }
    }

    @ViewBuilder
    private var cueDetail: some View {
        if let id = selectedCueID, let cue = LEDCueLibrary.cue(id: id) {
            CueDetailView(cue: cue, store: cueStore, stageState: stageState, tab: $cueTab)
                .id(cue.id)
        } else {
            ContentUnavailableView("Select a cue", systemImage: "sparkles")
        }
    }

    /// `.id(preset.id)` is load-bearing here, not decorative — see
    /// `UseCaseDetailView.init`'s doc comment: without it, switching which
    /// use case is selected would keep editing the first one's private
    /// `RingConfig` instead of loading the newly selected preset's.
    @ViewBuilder
    private var useCaseDetail: some View {
        if let id = selectedUseCaseID, let preset = useCaseStore.presets.first(where: { $0.id == id }) {
            UseCaseDetailView(
                preset: preset,
                store: useCaseStore,
                tab: $useCaseTab,
                stage: { config, playback, timeline in
                    AnyView(RingStage(
                        config: config, playback: playback, timeline: timeline, state: stageState
                    ))
                },
                code: { config in AnyView(ExportView(config: config)) }
            )
            .id(preset.id)
        } else {
            ContentUnavailableView("Select or create a use case", systemImage: "target")
        }
    }
}

private struct PreviewTab: View {
    @ObservedObject var config: RingConfig
    @ObservedObject var player: TimelinePlayer
    @ObservedObject var stageState: StageState
    /// Donates the event that shows `AddStepTip` — see
    /// `ParameterEditWatcher`.
    @StateObject private var editWatcher = ParameterEditWatcher()

    var body: some View {
        // One clock for the whole tab. `paused:` stops it dead when not
        // playing, so a parked timeline costs nothing.
        TimelineView(.animation(paused: !player.isPlaying)) { context in
            let now = player.currentTime(at: context.date)
            let playback = player.playback(at: context.date)

            VStack(spacing: 0) {
                // The canvas itself lives in `RingStage` — shared with the
                // Cue Library and Use Cases panes, which used to each have
                // their own lesser version of it.
                RingStage(
                    config: player.displayConfig(for: playback, fallback: config),
                    playback: playback,
                    timeline: player.timeline,
                    state: stageState,
                    // From the live config, never the resolved one — see
                    // `RingStage.previewDiameter`.
                    previewDiameter: config.previewDiameter
                )
                Divider()
                TimelineStripView(
                    player: player,
                    config: config,
                    playhead: now,
                    onScrub: { player.scrub(to: $0) }
                )
            }
        }
        .onAppear { editWatcher.watch(config) }
    }
}

/// Name prompt for creating or renaming a user section.
///
/// A sheet rather than an `.alert` with a `TextField`, matching
/// `SavedPresetsView`'s dialogs — see the comment there.
private struct SectionNameSheet: View {
    let title: String
    @Binding var name: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            TextField("Name", text: $name)
                .onSubmit(onConfirm)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .ringGlassButtonStyle()
                Button("Save", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .ringGlassButtonStyle()
            }
        }
        .padding()
        .frame(width: 320)
    }
}
