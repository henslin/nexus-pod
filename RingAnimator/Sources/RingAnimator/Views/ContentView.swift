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
    /// The sequencing document — see `TimelinePlayer`. Bound to `config`
    /// in `.onAppear` below, which is what makes the Controls panel edit
    /// the selected step in place rather than a detached scratch copy.
    @StateObject private var timelinePlayer = TimelinePlayer()
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
                                            deleteUserSection(userSection)
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
                SavedPresetsView(store: presetStore, config: config, timelinePlayer: timelinePlayer, useCaseStore: useCaseStore)
                    .listColumnWidth()
            case .cueLibrary:
                CueListView(store: cueStore, selectedCueID: $selectedCueID, searchText: $cueSearchText)
                    .listColumnWidth()
            case .useCases:
                UseCaseListView(store: useCaseStore, selectedUseCaseID: $selectedUseCaseID)
                    .listColumnWidth()
            case .user(let id):
                // The same list as Use Cases, over that section's own
                // store. `.id(id)` so switching sections rebuilds it
                // against the new store rather than keeping the old one.
                UseCaseListView(
                    store: store(forSection: id),
                    selectedUseCaseID: binding(forSection: id)
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
        .onAppear {
            showingWhatsNew = WhatsNewPresenter.shouldPresent()
            // Deferred to `.onAppear` rather than done in an initializer:
            // `@StateObject`s aren't guaranteed to be constructed until the
            // view first appears, and binding needs both objects to exist.
            timelinePlayer.bind(to: config)
        }
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
            return count == 0 ? purpose : "\(purpose) · \(count)"
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

    /// Where the playhead sits when the clock isn't running. Playback
    /// itself is computed from `TimelineView`'s own date (see
    /// `currentTime(at:)`) rather than accumulated into state frame by
    /// frame — writing state sixty times a second would both fight
    /// SwiftUI's render pass and republish through `player` for no reason.
    @State private var pausedPlayhead: Double = 0
    /// Wall-clock instant playback started, paired with the playhead
    /// position it started from. Rebuilt whenever play is pressed or the
    /// user scrubs mid-playback.
    @State private var playAnchor: (date: Date, offset: Double)?

    /// What the previews actually render. While a sequence is playing
    /// that's the player's own read-only config (see
    /// `TimelinePlayer.playbackConfig`); otherwise it's the live config,
    /// which — thanks to the Controls⇄segment binding — already *is* the
    /// selected step. So editing shows the step you're editing and playing
    /// shows the sequence, with no third state to keep in sync.
    private var displayConfig: RingConfig {
        player.isPlaying ? player.playbackConfig : config
    }

    var body: some View {
        // One clock for the whole tab. `paused:` stops it dead when not
        // playing, so a parked timeline costs nothing.
        TimelineView(.animation(paused: !player.isPlaying)) { context in
            let now = currentTime(at: context.date)
            let resolved = player.timeline.resolve(at: now)
            let playback = playbackFrame(for: resolved)

            VStack(spacing: 0) {
                // The canvas itself lives in `RingStage` — shared with the
                // Cue Library and Use Cases panes, which used to each have
                // their own lesser version of it.
                RingStage(
                    config: displayConfig,
                    playback: playback,
                    timeline: player.timeline,
                    state: stageState
                )
                Divider()
                TimelineStripView(
                    player: player,
                    config: config,
                    playhead: now,
                    onScrub: { scrub(to: $0) }
                )
            }
        }
        .onAppear { editWatcher.watch(config) }
        .onChange(of: player.isPlaying) { _, isPlaying in
            if isPlaying {
                playAnchor = (date: Date(), offset: pausedPlayhead)
            } else {
                // Freeze wherever the playhead had got to, so pressing play
                // again resumes instead of restarting.
                playAnchor.map { pausedPlayhead = $0.offset + Date().timeIntervalSince($0.date) }
                playAnchor = nil
            }
        }
    }

    /// Seconds into the timeline at a given wall-clock instant.
    private func currentTime(at date: Date) -> Double {
        guard let anchor = playAnchor else { return pausedPlayhead }
        return anchor.offset + date.timeIntervalSince(anchor.date)
    }

    private func scrub(to time: Double) {
        let clamped = max(time, 0)
        pausedPlayhead = clamped
        // Re-anchor rather than stop: scrubbing mid-playback should jump
        // and keep running, the way a video scrubber does.
        if player.isPlaying {
            playAnchor = (date: Date(), offset: clamped)
        }
    }

    /// Nil whenever nothing should override the ring's own clock — an
    /// empty timeline, or simply not playing. `TabBarPreview`/`RingView`
    /// both treat nil as "behave exactly as you always did".
    private func playbackFrame(for resolved: RingTimeline.Resolved?) -> TimelinePlayback? {
        guard player.isPlaying, let resolved else { return nil }
        player.prepareForPlayback(resolved)
        return TimelinePlayback(resolved)
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
