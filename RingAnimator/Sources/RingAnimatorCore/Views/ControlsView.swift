import SwiftUI

/// Mac app's Controls panel — a scrolling stack of collapsible Liquid Glass
/// cards, one per section, instead of one long `Form`. The section
/// *content* itself still lives in `ControlsSections.swift`, shared with
/// the iOS app's drill-down menu (`RingSettingsMenu`) so the two never
/// drift apart on a knob's range, default, or behavior — this file only
/// owns Mac's presentation: card chrome, expand/collapse, ordering, and
/// icons.
///
/// Two changes from the old single-`Form` layout:
///
/// 1. **Ordering** now groups "the ring's own look" (Color, Animation,
///    Shape, Motion Effects, Glow & Blend, Particles) ahead of "how it's
///    staged for this demo" (Playback, Voice, Background, Liquid Glass).
///    The old order mixed the two freely — Color was last, Voice sat in
///    the middle — which read as one long undifferentiated wall rather
///    than "core design, then testing/staging tools".
///
/// 2. **Collapsible cards** instead of always-open sections. A card starts
///    expanded only when its section is either a core-design section
///    (Color/Animation/Shape/Motion/Glow) or its own headline feature is
///    already in use (e.g. Particles opens expanded if `particlesEnabled`
///    was already true) — so a fresh design opens showing the handful of
///    sections you're actually about to touch, not every control at once.
///    Particles/Playback/Background also get a small switch right in the
///    card header (not just buried inside the collapsed content) so you
///    can flip the section on without needing to expand it first.
///
/// Moving off `Form` also means these cards no longer get System-applied
/// Liquid Glass chrome on their buttons for free the way rows inside a
/// `Form`/`List`/toolbar do (see `ExportView`'s equivalent comment) — that
/// tradeoff is deliberate here since it's what makes an explicit Liquid
/// Glass card background possible in the first place. The buttons that
/// live inside these cards (`BackgroundSection`, `VoiceSection`) pick up
/// `.ringGlassButtonStyle()` in `ControlsSections.swift` to compensate.
public struct ControlsView: View {
    @ObservedObject var config: RingConfig
    /// Commits the ring's current state as a timeline step. `nil` where
    /// there's no timeline to add to, which is what hides the button.
    var onAddToTimeline: (() -> Void)?
    /// Observed directly (rather than read through `config.elevenLabs`
    /// each time) so this view redraws when connection state, level, or
    /// transcripts change — see `RingConfig.elevenLabs`'s doc comment for
    /// why `RingView` doesn't need the same thing.
    @ObservedObject private var voice: ElevenLabsVoiceService
    /// Observed directly (same reasoning as `voice` above) so a listening
    /// failure — permission denied, no recognizer, engine wouldn't start —
    /// shows up immediately instead of silently doing nothing.
    @ObservedObject private var stt: SpeechToTextService

    @State private var expanded: [String: Bool]

    public init(config: RingConfig, onAddToTimeline: (() -> Void)? = nil) {
        self.config = config
        self.onAddToTimeline = onAddToTimeline
        self.voice = config.elevenLabs
        self.stt = config.voiceConversation.stt
        _expanded = State(initialValue: [
            "color": true,
            "animation": true,
            "shape": true,
            "motion": true,
            "glow": true,
            "particles": config.particlesEnabled,
            "playback": config.sequencePlaybackEnabled,
            "voice": config.voiceReactiveEnabled,
            "background": config.backgroundImageEnabled,
            "glass": false
        ])
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                card("color", "Color", "paintpalette", alignsAsForm: false) {
                    ColorSection(config: config)
                }

                // Only when a firmware pattern is loaded — see the type's
                // doc comment for why it isn't always present.
                if config.firmwarePatternStream != nil || config.firmwareLevelField != nil {
                    card("fidelity", "Firmware Fidelity", "checkmark.seal") {
                        FirmwareFidelitySection(config: config)
                    }
                }

                card("smoothing", "Smooth", "drop.halffull",
                     footer: "Spreads the hardware render in space and trails it in time — the same animation, without twenty hard edges. Off renders exactly what the device would. Preview only; the code exports stay hardware-accurate.",
                     masterToggle: $config.smoothingEnabled) {
                    SmoothingSection(config: config)
                }

                card("animation", "Animation", "play.circle") {
                    AnimationSection(config: config)
                }

                card("shape", "Shape", "circle.dashed") {
                    ShapeSection(config: config)
                }

                card("motion", "Motion Effects", "arrow.triangle.2.circlepath",
                     footer: "Layer these on top of any animation type above.") {
                    MotionEffectsSection(config: config)
                }

                card("glow", "Glow & Blend", "sun.max") {
                    GlowBlendSection(config: config)
                }

                card("particles", "Particles", "sparkles",
                     footer: "Raw CAEmitterLayer/CAEmitterCell controls — the same particle system UIKit/AppKit apps use.",
                     masterToggle: $config.particlesEnabled) {
                    ParticlesSection(config: config)
                }

                card("playback", "Playback", "repeat",
                     footer: "Off = loops forever, like a live status indicator. On = plays the same hold/fade envelope the Cue Library uses, so you can preview it as a one-shot cue.",
                     masterToggle: $config.sequencePlaybackEnabled) {
                    PlaybackSection(config: config)
                }

                card("voice", "Voice", "waveform",
                     footer: "Connects to a preconfigured ElevenLabs Conversational AI agent so the ring reacts to actual assistant speech instead of a simulated level.") {
                    VoiceSection(config: config, voice: voice, stt: stt)
                }

                card("background", "Background", "photo",
                     footer: "Shows behind the tab bar in the iPhone preview below — a manual way to test any reference PNG, on top of (and taking priority over) the bundled \"App UI\" screenshots. Doesn't affect the large preview.",
                     masterToggle: $config.backgroundImageEnabled) {
                    BackgroundSection(config: config)
                }

                card("glass", "Liquid Glass", "wand.and.stars",
                     footer: "The real Glass API's own parameters — style, tint, and interactive — applied to the floating tab bar and ring pod in the iPhone preview below, and the ring button on iOS.") {
                    LiquidGlassSection(config: config)
                }
            }
            .padding(16)
        }
        #if os(macOS)
        .frame(minWidth: 320)
        #endif
    }

    /// Wraps a section's shared content (from `ControlsSections.swift`) in
    /// a `GlassSectionCard`, binding its expanded state into `expanded`
    /// keyed by `id`. Kept as one call site per section (rather than a
    /// data-driven `ForEach`) since each section's footer text and
    /// optional header toggle differ — explicit call sites read as clearly
    /// here as the old file's explicit `Section { ... }` blocks did.
    @ViewBuilder
    private func card<Content: View>(
        _ id: String,
        _ title: String,
        _ systemImage: String,
        footer: String? = nil,
        masterToggle: Binding<Bool>? = nil,
        alignsAsForm: Bool = true,
        // `@escaping` because `GlassSectionCard.content` is a stored
        // property, not a parameter — Swift requires any closure that
        // outlives the function call it was passed into (i.e. gets stored
        // rather than just invoked inline) to be escaping, so this needs
        // to be explicit even though `card(...)` itself just forwards it
        // straight through to `GlassSectionCard`'s memberwise init.
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        GlassSectionCard(
            title: title,
            systemImage: systemImage,
            footer: footer,
            masterToggle: masterToggle,
            alignsAsForm: alignsAsForm,
            onReset: ControlsSectionReset.isResettable(id)
                ? { ControlsSectionReset.reset(id, on: config) }
                : nil,
            onAddToTimeline: onAddToTimeline,
            isExpanded: Binding(
                get: { expanded[id, default: true] },
                set: { expanded[id] = $0 }
            ),
            content: content
        )
    }
}

// `GlassSectionCard` itself now lives in `GlassSectionCard.swift`, public so
// `CueExplorerView` (in the main `RingAnimator` target) can build on the
// exact same card for the Cue Library's per-cue editor.
