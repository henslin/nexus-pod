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

    public init(config: RingConfig) {
        self.config = config
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
                card("color", "Color", "paintpalette") {
                    ColorSection(config: config)
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
            isExpanded: Binding(
                get: { expanded[id, default: true] },
                set: { expanded[id] = $0 }
            ),
            content: content
        )
    }
}

/// One collapsible card — the Liquid Glass equivalent of a `Form` grouped
/// `Section`, but as its own standalone floating shape instead of a row in
/// one continuous list background. Falls back to `.regularMaterial` on
/// pre-26 systems, the same `#available` pattern as `ContentView.glassRing`
/// and `ExportView`'s toolbar buttons.
private struct GlassSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    var footer: String? = nil
    var masterToggle: Binding<Bool>? = nil
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: systemImage)
                            .foregroundStyle(.secondary)
                        Text(title)
                            .font(.headline)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                if let masterToggle {
                    Toggle("", isOn: masterToggle)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        #if os(macOS)
                        .controlSize(.small)
                        #endif
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    content()
                    if let footer {
                        Text(footer)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        // Without this, the collapse/expand transition's opacity+move
        // animates the content sliding and fading past the card's own
        // edges instead of being masked by them — the rounded-rect glass
        // background sits behind an unclipped VStack, so a section with
        // tall content briefly overflows the card's shape mid-animation.
        // Clipping to the same shape `cardBackground()` draws keeps every
        // frame of the collapse contained to the card, not just the
        // settled start/end states.
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .cardBackground()
    }
}

private extension View {
    @ViewBuilder
    func cardBackground() -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}
