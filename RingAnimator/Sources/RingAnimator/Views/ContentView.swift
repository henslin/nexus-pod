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
    @State private var designerTab: DesignerTab = .preview
    @State private var cueTab: DesignerTab = .preview
    @State private var selectedCueID: String? = LEDCueLibrary.all.first?.id
    @State private var cueSearchText: String = ""
    @State private var selectedUseCaseID: RingPreset.ID?
    /// The post-update release notes — see `WhatsNewPresenter` for when
    /// they're due. Also reachable on demand from the Help menu, which is
    /// where macOS users look for "what changed".
    @State private var showingWhatsNew = false

    enum AppSection: String, CaseIterable, Identifiable, Hashable {
        case ringDesigner = "Nexus"
        case cueLibrary = "Cue Library"
        case useCases = "Use Cases"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .ringDesigner: return "sparkles"
            case .cueLibrary: return "books.vertical"
            case .useCases: return "target"
            }
        }
    }

    enum DesignerTab: String, CaseIterable, Identifiable {
        case preview = "Preview"
        case export = "Export Code"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationSplitView {
            // A plain `ForEach` here (rather than the `List(data:selection:
            // content:)` shorthand) so a `Divider()` can sit between Cue
            // Library and Use Cases — visually groups them apart from
            // Nexus without needing a full `Section` header for just two
            // items.
            List(selection: $section) {
                ForEach(AppSection.allCases) { item in
                    Label(item.rawValue, systemImage: item.icon).tag(item)
                    if item == .cueLibrary {
                        Divider()
                    }
                }
            }
            .navigationSplitViewColumnWidth(180)
        } content: {
            switch section {
            case .ringDesigner:
                SavedPresetsView(store: presetStore, config: config, timelinePlayer: timelinePlayer, useCaseStore: useCaseStore)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
            case .cueLibrary:
                CueListView(store: cueStore, selectedCueID: $selectedCueID, searchText: $cueSearchText)
                    .navigationSplitViewColumnWidth(min: 260, ideal: 300)
            case .useCases:
                UseCaseListView(store: useCaseStore, selectedUseCaseID: $selectedUseCaseID)
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
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
            case .none:
                EmptyView()
            }
        }
        // No `.navigationTitle`. On this macOS it renders at the top of the
        // *content column*, not just in the title bar — so whatever it said
        // sat directly above the list, restating the row already
        // highlighted an inch below it. The section name was redundant with
        // the sidebar; the selection was redundant with the list. Neither
        // earned the most prominent text in the window, and the column's
        // own controls are better use of that space.
        .sheet(isPresented: $showingWhatsNew) {
            WhatsNewView {
                WhatsNewPresenter.markSeen()
                showingWhatsNew = false
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


    @ViewBuilder
    private var designerDetail: some View {
        // Both tabs stay mounted the whole time instead of a `switch` that
        // swaps one for the other — a `switch` gives each case a different
        // branch identity, so SwiftUI tears down and rebuilds whichever
        // view isn't showing from scratch. That silently reset every piece
        // of `PreviewTab`'s own state on every trip back to Preview: the
        // Large Preview card's corner/collapsed state, and — worse —
        // `PhoneMockupView`'s `ZoomableCanvas`, whose pan/zoom lives in a
        // wrapped `NSScrollView` that has no SwiftUI state to restore once
        // its `NSViewRepresentable` itself gets recreated. Keeping both
        // views alive and just toggling which one is visible/hit-testable
        // preserves all of that across tab switches, matching what a
        // person expects from "the two panes I keep flipping between."
        ZStack {
            PreviewTab(config: config, player: timelinePlayer, stageState: stageState)
                .opacity(designerTab == .preview ? 1 : 0)
                .allowsHitTesting(designerTab == .preview)
                .accessibilityHidden(designerTab != .preview)
            ExportView(config: config)
                .opacity(designerTab == .export ? 1 : 0)
                .allowsHitTesting(designerTab == .export)
                .accessibilityHidden(designerTab != .export)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $designerTab) {
                    ForEach(DesignerTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
        }
    }

    @ViewBuilder
    private var cueDetail: some View {
        if let id = selectedCueID, let cue = LEDCueLibrary.cue(id: id) {
            Group {
                switch cueTab {
                case .preview:
                    CueDetailView(cue: cue, store: cueStore, stageState: stageState)
                case .export:
                    CueExportView(cue: cue, store: cueStore)
                }
            }
            .id(cue.id)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $cueTab) {
                        ForEach(DesignerTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }
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
            UseCaseDetailView(preset: preset, store: useCaseStore) { config, playback, timeline in
                AnyView(RingStage(
                    config: config, playback: playback, timeline: timeline, state: stageState
                ))
            }
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
