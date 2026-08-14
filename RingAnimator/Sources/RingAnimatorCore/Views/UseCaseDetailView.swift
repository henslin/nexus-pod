import SwiftUI
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

    /// Caller (`ContentView`) is expected to key this view with
    /// `.id(preset.id)` at the call site — a `@StateObject` only runs its
    /// initial-value closure once per view *identity*, so without that,
    /// switching which use case is selected would keep editing the first
    /// one's `editingConfig` instead of loading the newly selected preset.
    public init(preset: RingPreset, store: RingPresetStore) {
        self.store = store
        self.presetID = preset.id
        let config = RingConfig()
        preset.apply(to: config)
        _editingConfig = StateObject(wrappedValue: config)
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
        HSplitView {
            previewPane
                .frame(minWidth: 420, idealWidth: 640)
            controlsPanel
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 340)
        }
        .onReceive(editingConfig.objectWillChange.debounce(for: .seconds(0.3), scheduler: RunLoop.main)) { _ in
            persist()
        }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                centeredPreview
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var controlsPanel: some View {
        ScrollView {
            controls
                .padding(16)
        }
    }

    private var header: some View {
        Text(currentPreset?.name ?? "Use Case")
            .font(.title2.bold())
    }

    private var centeredPreview: some View {
        VStack(spacing: 12) {
            RingView(config: editingConfig, diameter: 200)
                .frame(width: 260, height: 260)
                .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.black.opacity(0.9)))
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
            isExpanded: Binding(
                get: { expanded[id, default: true] },
                set: { expanded[id] = $0 }
            ),
            content: content
        )
    }
}
