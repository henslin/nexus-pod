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
/// Which aspect of the selected state the panel is inspecting.
///
/// Keynote's model, and Chris's proposal (2026-09-10): one selected thing,
/// several inspectors onto it — Format/Animate/Document. **Not three
/// libraries.** A state of the Nexus tab is a `RingPreset`, which already
/// captures the ring, the pod content, the status message and the tint in
/// one snapshot; splitting the panel into three stores would mean a second
/// store, a second detail view, and a rule for what happens when a status
/// and an animation disagree about the same pod. These are views onto the
/// one config.
///
/// **This is the panel's one legitimate segmented control.** A segmented
/// control switches what a view *displays*, which is exactly this; the
/// value pickers inside the cards stay menus. Two controls with different
/// jobs is correct — it was two controls doing the *same* job that was the
/// bug when Glass Style was segmented among eleven menus.
public enum ControlsAspect: String, CaseIterable, Identifiable {
    /// Per-state: how the ring itself moves and is coloured.
    case animation
    /// Per-state: what the pod shows, and what the accessory says.
    case status
    /// App-wide: the assistant. Already global by construction —
    /// `RingPreset` excludes every voice/ElevenLabs field, because a live
    /// connection setting (and an API key) is not part of an animation.
    case agent
    /// App-wide: the surrounding app rather than any one state.
    ///
    /// This formalises a distinction `RingPreset` already made silently by
    /// *omission* — it deliberately leaves out `previewDiameter`, the
    /// background staging image, and the voice fields as "not really part
    /// of the animation". Naming it means the rule is visible instead of
    /// discoverable only by reading which fields a snapshot skips.
    case global

    public var id: String { rawValue }

    /// Whether this aspect edits the selected state or the whole app. Not
    /// used for layout yet; it is here so the distinction is stated once
    /// rather than implied by which cards happen to sit where.
    var isPerState: Bool { self == .animation || self == .status }

    var label: String {
        switch self {
        case .animation: return "Animation"
        case .status:    return "Status"
        case .agent:     return "AI Agent"
        case .global:    return "Global"
        }
    }

    /// Chris's mapping (2026-09-10), and it is the one that reads: the
    /// ring for the thing that animates, a message bubble for the thing
    /// that says something, sparkles for the agent, a gear for app-wide.
    /// The previous set — `play.circle`/`circle.circle`/`waveform` — named
    /// mechanisms rather than subjects, and two of them were both circles.
    ///
    /// `circle` is deliberately the plain outline: at this weight it draws
    /// as a ring, which is the product's own mark. All four are verified
    /// to resolve on this SF Symbols version — an unknown name draws
    /// nothing at all, silently.
    var symbol: String {
        switch self {
        case .animation: return "circle"
        case .status:    return "ellipsis.message"
        case .agent:     return "sparkles"
        case .global:    return "gearshape"
        }
    }
}

/// Keynote's inspector switcher: a Liquid Glass capsule of glyphs, with
/// the selection sliding between them.
///
/// **Custom arrangement, system materials** — the standing rule. The stock
/// `.pickerStyle(.segmented)` was tried first and doesn't carry the glass
/// this needs at the size it needs, so the *layout* is hand-built while
/// every surface stays a real API: `GlassEffectContainer` +
/// `.glassEffect(.regular.interactive(), in: Capsule())` for the capsule,
/// and `.fill.tertiary` for the selection — the system's own adaptive fill
/// for sitting on vibrant/glass materials, which is exactly what
/// `TabBarPreview` uses for the selected tab. Nothing here is a hand-drawn
/// approximation of a material.
///
/// The selection is `.fill.tertiary` rather than a second `glassEffect`
/// on purpose: glass over glass sits visibly proud, and Keynote's selected
/// segment is flush.
///
/// Glyph-only with the name on hover, like Keynote — four labels across a
/// 320pt panel crowd it, and the tooltip covers the first encounter.
struct AspectSwitcher: View {
    @Binding var aspect: ControlsAspect

    /// Drives the selection capsule's slide between segments.
    @Namespace private var selection

    private static let segmentWidth: CGFloat = 52
    private static let height: CGFloat = 34

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            // `spacing: 0` — this is the distance within which glass shapes
            // *merge*, which works opposite to stack spacing. There is one
            // shape here, so there is nothing to merge.
            GlassEffectContainer(spacing: 0) {
                segments.glassEffect(.regular.interactive(), in: Capsule())
            }
        } else {
            segments.background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var segments: some View {
        HStack(spacing: 0) {
            ForEach(ControlsAspect.allCases) { a in
                segment(a)
            }
        }
        .padding(3)
    }

    private func segment(_ a: ControlsAspect) -> some View {
        let isSelected = a == aspect
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                aspect = a
            }
        } label: {
            Image(systemName: a.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: Self.segmentWidth, height: Self.height)
                // Before any padding, not after — a hit area applied
                // outside padding covers the padded frame instead of the
                // control, which is how a whole tab bar once became
                // untappable while looking perfectly correct.
                .contentShape(Capsule())
                .background {
                    if isSelected {
                        Capsule()
                            .fill(.fill.tertiary)
                            .matchedGeometryEffect(id: "aspectSelection", in: selection)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a.label)
        .help(a.label)
    }
}

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
    /// Which inspector is showing. Not persisted: it is a view state, and
    /// coming back to the panel on the aspect you were last editing is
    /// less useful than coming back to the ring, which is what the app is
    /// mostly for.
    @State private var aspect: ControlsAspect = .animation

    public init(config: RingConfig) {
        self.config = config
        self.voice = config.elevenLabs
        self.stt = config.voiceConversation.stt
        _expanded = State(initialValue: [
            "motion": true,
            "shape": true,
            "color": true,
            "sweep": true,
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
                // The aspect switcher. Pinned at the top of the panel
                // rather than in a toolbar so it reads as belonging to
                // this inspector, the way Keynote's does.
                AspectSwitcher(aspect: $aspect)

                switch aspect {
                case .animation: animationCards
                case .status:    statusCards
                case .agent:     agentCards
                case .global:    globalCards
                }
            }
            .padding(16)
        }
        #if os(macOS)
        .frame(minWidth: 320)
        #endif
    }

    // MARK: - Animation
    //
    // How the ring itself moves and is coloured: the app's original
    // subject, and still the deepest of the three.

    @ViewBuilder
    private var animationCards: some View {
        Group {
            // Top to bottom is the order of operations for making an
            // animation (2026-09-14): what it does, what it looks like, how
            // it renders, what finishes it, what it is at rest, how it
            // plays. Each card answers one question.

            // 1. What does it do?
            card("motion", "Motion", "play.circle") {
                MotionSection(config: config)
            }

            card("shape", "Shape", "circle.dashed") {
                ShapeSection(config: config)
            }

            // 2. What does it look like?
            card("color", "Color", "paintpalette", alignsAsForm: false) {
                ColorSection(config: config)
            }

            card("sweep", "Sweep", "circle.lefthalf.filled.righthalf.striped.horizontal",
                 footer: "How the colours are drawn around the ring, as distinct from which colours. Perceptual is the default; the shader is the per-pixel version with room to explore.") {
                SweepSection(config: config)
            }

            // 3. How does it render? The hardware trio, in order.
            card("hardware", "Hardware", "cpu",
                 footer: "The animation as a fixed ring of diodes, the way addressable LED hardware works, and everything that follows from that.",
                 masterToggle: $config.diodeModeEnabled) {
                HardwareSection(config: config)
            }

            card("smoothing", "Smooth", "drop.halffull",
                 footer: "Spreads the hardware render in space and trails it in time — the same animation, without twenty hard edges. Off renders exactly what the device would. Preview only; the code exports stay hardware-accurate.",
                 masterToggle: $config.smoothingEnabled) {
                SmoothingSection(config: config)
            }

            // Only when a firmware pattern is loaded — see the type's
            // doc comment for why it isn't always present.
            if config.firmwarePatternStream != nil || config.firmwareLevelField != nil {
                card("fidelity", "Firmware Fidelity", "checkmark.seal") {
                    FirmwareFidelitySection(config: config)
                }
            }

            // 4. What finishes it?
            card("glow", "Glow & Blend", "sun.max") {
                GlowBlendSection(config: config)
            }

            card("particles", "Particles", "sparkles",
                 footer: "A CAEmitterLayer particle system driven by the ring's own colors and speed.",
                 masterToggle: $config.particlesEnabled) {
                ParticlesSection(config: config)
            }

            // 5. What is it at rest?
            card("neutral", "Neutral State", "circle.dotted.circle",
                 footer: "The ring when nothing is happening. Brightness at zero with the diffuser on is the frosted-glass resting state, like Harpy and Ziris at rest. Saved with the state, so a sequence can settle into it.") {
                NeutralStateSection(config: config)
            }

            // 6. How does it play?
            card("playback", "Playback", "play.rectangle",
                 footer: "Fade in, hold, fade out — the envelope one step plays with in a sequence.",
                 masterToggle: $config.sequencePlaybackEnabled) {
                PlaybackSection(config: config)
            }
        }
    }

    // MARK: - Status
    //
    // What the pod shows, and what the accessory above the bar says. The
    // pod's material lives here too: the tinted fill is a status colour,
    // so Liquid Glass belongs beside the thing that tints it.

    @ViewBuilder
    private var statusCards: some View {
        Group {
            card("pod", "Pod Content", "circle.circle",
                 footer: "What the pod shows in the tab bar — the animated ring, a host-supplied photo, or a glyph — and the message that spawns above the bar with it.") {
                PodContentSection(config: config)
            }

        }
    }

    // MARK: - Global
    //
    // The surrounding app, not any one state. A real host app does not
    // restyle its tab bar material per notification, so glass is one
    // setting for the whole app rather than something each state carries.
    //
    // **Preview Size deliberately stays in Shape**, even though it is
    // global by the same test (`RingPreset` omits it). It sits directly
    // under Ring Size because the two sound alike and separating them is
    // what made the ring's own diameter read as missing — see CLAUDE.md,
    // "Ring Size and Preview Size are different questions". Taxonomy is
    // not worth reintroducing a fixed confusion.

    @ViewBuilder
    private var globalCards: some View {
        Group {
            card("tabs", "Tabs", "square.grid.2x2",
                 footer: "The host app's own tab names and glyphs. App-wide, like the glass — a real tab bar doesn't rename itself per notification.") {
                TabsSection(config: config)
            }

            card("glass", "Liquid Glass", "wand.and.stars",
                 footer: "The real Glass API's own parameters — style, tint, and interactive — applied to the floating tab bar and pod. App-wide: every state shares one material.") {
                LiquidGlassSection(config: config)
            }

            card("background", "Background", "photo",
                 footer: "Shows behind the tab bar in the iPhone preview — a manual way to test any reference PNG, on top of (and taking priority over) the bundled \"App UI\" screenshots. Staging only; never saved with a state.",
                 masterToggle: $config.backgroundImageEnabled) {
                BackgroundSection(config: config)
            }
        }
    }

    // MARK: - AI agent

    @ViewBuilder
    private var agentCards: some View {
        Group {
                card("voice", "Voice", "waveform",
                     footer: "Connects to a preconfigured ElevenLabs Conversational AI agent so the ring reacts to actual assistant speech instead of a simulated level.") {
                    VoiceSection(config: config, voice: voice, stt: stt)
                }

        }
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
