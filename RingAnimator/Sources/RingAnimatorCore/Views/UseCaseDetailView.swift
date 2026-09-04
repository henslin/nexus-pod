import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif
import Combine

/// Detail pane for one "Use Case" — a named, fully-tunable `RingPreset`
/// (see `RingPresetStore`) a team member creates for a specific scenario
/// (e.g. "Low Battery Warning", "Order Shipped"), independent of whatever's
/// currently loaded into Nexus's own shared `RingConfig`.
///
/// Built directly on the same section structs Nexus's own `ControlsView`
/// uses (`ColorSection`, `AnimationSection`, ... from
/// `ControlsSections.swift`), bound to this use case's own private
/// `RingConfig` — not a hand-rolled control set — so "every animation
/// control is available" genuinely means every control `RingPreset` can
/// persist, with zero risk of drifting out of sync with Nexus's own
/// Controls panel. Lives in `RingAnimatorCore` (like `ControlsView`
/// itself) specifically so it can reach those section structs directly;
/// `UseCaseListView` (the list column, which needs `NSSavePanel`/
/// `NSOpenPanel`) stays in the main `RingAnimator` target, the same split
/// `ControlsView`/`SavedPresetsView` already use.
///
/// Two `ControlsView` cards are deliberately left out — Voice and
/// Background — for the same reason `RingPreset` itself already excludes
/// both fields: Voice is a live ElevenLabs connection, not a property of
/// the animation, and Background is a manual preview-staging reference
/// image, not something a use case's *animation* should carry. Showing
/// either here would silently fail to persist across a reload, since
/// `RingPreset` has nowhere to store them — every other section (Color
/// through Liquid Glass) is here, unconditionally.
///
/// Autosaves continuously rather than needing an explicit Save step — the
/// same "no separate save step, only editing" convention `CueDetailView`
/// established for the Cue Library. Debounced off `editingConfig`'s own
/// `objectWillChange` (rather than an explicit `onChange` per field, which
/// `RingConfig`'s several dozen `@Published` properties make impractical
/// to enumerate one by one) so a fast drag on a slider coalesces into one
/// write instead of one per intermediate value.
public struct UseCaseDetailView: View {
    @ObservedObject var store: RingPresetStore
    let presetID: RingPreset.ID
    @StateObject private var editingConfig: RingConfig
    @State private var expanded: [String: Bool]

    /// This use case's own sequence, in its own store — see
    /// `TimelinePlayer.useCaseFileName`. Created per view identity, which
    /// the `.id(preset.id)` at the call site already guarantees is one per
    /// use case.
    @StateObject private var player: TimelinePlayer

    /// Where the playhead sits while stopped. Playback itself is computed
    /// from `TimelineView`'s own date, so nothing republishes per frame —
    /// same arrangement as the Mac app's Preview tab.
    @State private var pausedPlayhead: Double = 0
    /// Same tip as Nexus — see `AddStepTip`. Shown once ever, so whichever
    /// pane you first change a parameter in gets it.
    @StateObject private var editWatcher = ParameterEditWatcher()

    /// Builds the canvas this pane previews on, given the config to render
    /// and the current playback frame.
    ///
    /// Injected rather than built here because the good canvas — the
    /// zoomable phone mockup with the floating Large Preview, `RingStage` —
    /// is AppKit all the way down (`ZoomableCanvas` wraps a real
    /// `NSScrollView`), and this type lives in the shared core so it can
    /// reach `ControlsSections.swift`'s internal section structs. The macOS
    /// app passes the stage in; anything that can't falls back to
    /// `centeredPreview` below, which is what this pane had before.
    /// The timeline comes along so the stage can offer the sequence as an
    /// export source — the same thing Nexus hands `PhoneMockupView`.
    public typealias StageBuilder = @MainActor (RingConfig, TimelinePlayback?, RingTimeline) -> AnyView
    private let stage: StageBuilder?

    #if os(macOS)
    /// Non-nil while a Blender import report is up — see
    /// `BlenderImportReportView`. Guarded because the type it holds is
    /// itself macOS-only: the import needs `NSOpenPanel`, and iOS has no
    /// file picker wired up here.
    @State private var blenderReport: UseCaseBlenderReport?
    #endif

    /// Caller (`ContentView`) is expected to key this view with
    /// `.id(preset.id)` at the call site — a `@StateObject` only runs its
    /// initial-value closure once per view *identity*, so without that,
    /// switching which use case is selected would keep editing the first
    /// one's `editingConfig` instead of loading the newly selected preset.
    public init(
        preset: RingPreset,
        store: RingPresetStore,
        stage: StageBuilder? = nil
    ) {
        self.store = store
        self.presetID = preset.id
        self.stage = stage
        let config = RingConfig()
        preset.apply(to: config)
        _editingConfig = StateObject(wrappedValue: config)
        _player = StateObject(wrappedValue: TimelinePlayer(fileName: TimelinePlayer.useCaseFileName(preset.id)))
        // Same defaults as Nexus's own Controls panel (`ControlsView.init`).
        _expanded = State(initialValue: [
            "color": true,
            "animation": true,
            "shape": true,
            "motion": true,
            "glow": true,
            "particles": config.particlesEnabled,
            "playback": config.sequencePlaybackEnabled,
            "glass": false
        ])
    }

    /// Always read live off the store rather than cached in local `@State`
    /// — so a rename from `UseCaseListView`'s row context menu (a separate
    /// write straight to `store`) shows up here immediately, and so
    /// `persist()` below never risks clobbering a just-renamed name with a
    /// stale local copy.
    private var currentPreset: RingPreset? {
        store.presets.first(where: { $0.id == presetID })
    }

    public var body: some View {
        platformLayout
            #if os(macOS)
            // Run from the Use Cases column's own button — see
            // `UseCaseListView.importBlenderButton` for why it's posted
            // rather than called. Only the selected use case's detail view
            // is mounted, so this fires once, on the right one.
            .onReceive(NotificationCenter.default.publisher(for: .importBlenderIntoUseCase)) { _ in
                importBlenderScript()
            }
            #endif
            .onReceive(editingConfig.objectWillChange.debounce(for: .seconds(0.3), scheduler: RunLoop.main)) { _ in
                persist()
            }
            #if os(macOS)
            .sheet(item: $blenderReport) { report in
                BlenderImportReportView(fileName: report.fileName, outcome: report.outcome) {
                    blenderReport = nil
                }
            }
            #endif
    }

    /// `HSplitView` is a macOS-only API, but this type lives in the shared
    /// `RingAnimatorCore` target (needed for direct access to
    /// `ControlsSections.swift`'s internal section structs — see the type's
    /// own doc comment), so it has to compile for iOS too even though
    /// `UseCaseListView` — the Mac-only list that actually creates/selects a
    /// use case — has no iOS entry point yet. A stacked layout here keeps
    /// this genuinely usable if iOS ever grows its own way to reach this
    /// screen, rather than leaving a dead `#if os(macOS)` stub around the
    /// whole view.
    @ViewBuilder
    private var platformLayout: some View {
        #if os(macOS)
        HSplitView {
            previewPane
                .frame(minWidth: 420, idealWidth: 640)
            controlsPanel
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 340)
        }
        #else
        VStack(spacing: 0) {
            previewPane
            Divider()
            controlsPanel
        }
        #endif
    }

    private func persist() {
        guard let current = currentPreset else { return }
        let updated = RingPreset(id: presetID, name: current.name, createdAt: current.createdAt, config: editingConfig)
        store.update(updated)
    }

    /// Left/center pane: the use case's name and a live, centered preview —
    /// same shape as `CueDetailView.previewPane`, minus the spec-sheet
    /// reference text (use cases have no canned spec to compare against).
    private var previewPane: some View {
        // One clock for the pane, stopped dead when nothing is playing.
        TimelineView(.animation(paused: !player.isPlaying)) { context in
            let now = player.currentTime(at: context.date)
            let playback = player.playback(at: context.date)

            VStack(spacing: 0) {
                if let stage {
                    // No header above the stage — same reasoning as the Cue
                    // Library's pane: it made this section's canvas shorter
                    // than Nexus's for no visible reason. The name is in the
                    // window title.
                    stage(displayConfig, playback, player.timeline)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            // Only the fallback pane names the use case
                            // inline. Where a stage is injected the name is
                            // in the window title; here there's no title bar
                            // to put it in.
                            Text(currentPreset?.name ?? "Use Case")
                                .font(.title2.bold())
                            centeredPreview(playback: playback)
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Divider()
                TimelineStripView(
                    player: player,
                    config: editingConfig,
                    playhead: now,
                    onScrub: { player.scrub(to: $0) }
                )
            }
        }
        .onAppear {
            // Deferred for the same reason ContentView defers it:
            // `@StateObject`s aren't guaranteed constructed until first
            // appearance, and binding needs both objects to exist.
            player.bind(to: editingConfig)
            editWatcher.watch(editingConfig)
        }
    }

    /// What the preview renders — the player's read-only playback config
    /// while a sequence runs, the live editing config otherwise. Same split
    /// as `PreviewTab.displayConfig`: while paused the editing config
    /// already *is* the selected step.
    private var displayConfig: RingConfig {
        player.isPlaying ? player.playbackConfig : editingConfig
    }

    private var controlsPanel: some View {
        // Just the controls. Import Blender used to sit above them, and
        // moved to the top of the Use Cases column: it isn't *about* these
        // parameters, it replaces most of them.
        ScrollView {
            controls
                .padding(16)
        }
    }


    #if os(macOS)
    /// Interprets a Blender ring script into this use case's config — the
    /// same importer the Nexus panel uses, applied to `editingConfig` so it
    /// autosaves through the same path as any other edit here.
    private func importBlenderScript() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "py") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a Blender LED-ring script (.py)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let (text, delegatedTo) = BlenderScriptImporter.readScriptFollowingDelegation(at: url) else {
            blenderReport = UseCaseBlenderReport(url.lastPathComponent, BlenderScriptImporter.Outcome(
                applied: [],
                dropped: [],
                caveat: "Couldn't read this file as text — it isn't UTF-8, Latin-1, Mac Roman or UTF-16. Nothing was changed."
            ))
            return
        }

        if case .success = CodeGenerators.applyBlenderCode(text, to: editingConfig) {
            blenderReport = UseCaseBlenderReport(url.lastPathComponent, BlenderScriptImporter.Outcome(
                applied: ["Read this app's own NEXUS_PARAMS block — an exact round-trip, not an interpretation."],
                dropped: [],
                caveat: nil
            ))
            return
        }
        let hadSteps = !player.timeline.segments.isEmpty
        var outcome = BlenderScriptImporter.apply(text, to: editingConfig)
        // Say so when the chosen file only hands off to another one, rather
        // than silently reporting a pattern the user didn't pick.
        if let delegatedTo, !outcome.applied.isEmpty {
            outcome.applied.insert(
                "This pattern hands off to \(delegatedTo) — imported from there",
                at: 0
            )
        }
        // A multi-phase pattern arrives as steps. Installing them replaces
        // this use case's timeline and selects the first step, which loads
        // it back into `editingConfig` — so the ring shows phase one rather
        // than whatever the flattened config happened to hold.
        if !outcome.applied.isEmpty {
            // Always install, phases or not — an empty timeline clears any
            // steps left from a previous import so the strip and the ring
            // agree on which pattern is loaded.
            player.installImported(outcome.timeline ?? RingTimeline())
            if outcome.timeline == nil, hadSteps {
                outcome.applied.append("Single looping behavior → cleared the previous pattern's timeline steps")
            }
        }
        blenderReport = UseCaseBlenderReport(url.lastPathComponent, outcome)
    }
    #endif

    private func centeredPreview(playback: TimelinePlayback?) -> some View {
        VStack(spacing: 12) {
            LargePreviewCard(diameter: 200) {
                RingView(config: displayConfig, diameter: 200, overrideElapsed: playback?.elapsed)
                    .opacity(playback?.opacity ?? 1)
            }
            VStack(spacing: 4) {
                Text(editingConfig.animationType.rawValue).font(.headline)
                Text("Primary \(editingConfig.primaryColor.hexString) · Secondary \(editingConfig.secondaryColor.hexString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    /// Same card set, order, and icons as `ControlsView.body`, minus Voice
    /// and Background — see this type's doc comment for why.
    private var controls: some View {
        VStack(spacing: 12) {
            card("color", "Color", "paintpalette") {
                ColorSection(config: editingConfig)
            }

            // Same placement and rule as Nexus (see `ControlsView`): above
            // Animation because it overrides it, and absent when no
            // firmware pattern is loaded.
            if editingConfig.firmwarePatternStream != nil || editingConfig.firmwareLevelField != nil {
                card("fidelity", "Firmware Fidelity", "checkmark.seal") {
                    FirmwareFidelitySection(config: editingConfig)
                }
            }

            card("smoothing", "Smooth", "drop.halffull",
                 footer: "Spreads the hardware render in space and trails it in time — the same animation, without twenty hard edges. Off renders exactly what the device would. Preview only; the code exports stay hardware-accurate.",
                 masterToggle: $editingConfig.smoothingEnabled) {
                SmoothingSection(config: editingConfig)
            }

            card("animation", "Animation", "play.circle") {
                AnimationSection(config: editingConfig)
            }

            card("shape", "Shape", "circle.dashed") {
                ShapeSection(config: editingConfig)
            }

            card("motion", "Motion Effects", "arrow.triangle.2.circlepath",
                 footer: "Layer these on top of any animation type above.") {
                MotionEffectsSection(config: editingConfig)
            }

            card("glow", "Glow & Blend", "sun.max") {
                GlowBlendSection(config: editingConfig)
            }

            card("particles", "Particles", "sparkles",
                 footer: "Raw CAEmitterLayer/CAEmitterCell controls — the same particle system UIKit/AppKit apps use.",
                 masterToggle: $editingConfig.particlesEnabled) {
                ParticlesSection(config: editingConfig)
            }

            card("playback", "Playback", "repeat",
                 footer: "Off = loops forever, like a live status indicator. On = plays the same hold/fade envelope the Cue Library uses, so you can preview it as a one-shot cue.",
                 masterToggle: $editingConfig.sequencePlaybackEnabled) {
                PlaybackSection(config: editingConfig)
            }

            card("glass", "Liquid Glass", "wand.and.stars",
                 footer: "The real Glass API's own parameters — style, tint, and interactive — applied to this preview.") {
                LiquidGlassSection(config: editingConfig)
            }
        }
    }

    @ViewBuilder
    private func card<Content: View>(
        _ id: String,
        _ title: String,
        _ systemImage: String,
        footer: String? = nil,
        masterToggle: Binding<Bool>? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        GlassSectionCard(
            title: title,
            systemImage: systemImage,
            footer: footer,
            masterToggle: masterToggle,
            onReset: ControlsSectionReset.isResettable(id)
                ? { ControlsSectionReset.reset(id, on: editingConfig) }
                : nil,
            isExpanded: Binding(
                get: { expanded[id, default: true] },
                set: { expanded[id] = $0 }
            ),
            content: content
        )
    }
}


#if os(macOS)
/// One Blender import's result, wrapped for `sheet(item:)`.
struct UseCaseBlenderReport: Identifiable {
    let id = UUID()
    let fileName: String
    let outcome: BlenderScriptImporter.Outcome

    init(_ fileName: String, _ outcome: BlenderScriptImporter.Outcome) {
        self.fileName = fileName
        self.outcome = outcome
    }
}
#endif
