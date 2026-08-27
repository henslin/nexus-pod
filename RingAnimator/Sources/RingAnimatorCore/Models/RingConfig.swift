import SwiftUI
import Combine

/// All the tunable parameters exposed in the Controls panel.
/// This object is also what the code exporters read from, so every
/// property here should have a direct equivalent in the generated
/// SwiftUI and Jetpack Compose code.
public final class RingConfig: ObservableObject {
    private var cancellables = Set<AnyCancellable>()

    public init() {
        elevenLabsAPIKey = KeychainHelper.load(account: Self.elevenLabsAPIKeyAccount) ?? ""
        voiceConversation = VoiceConversationController(elevenLabs: elevenLabs)

        // The hands-free voice loop should run when "Voice reactive" is on
        // and either there's a live ElevenLabs connection to actually talk
        // to, or the temporary demo toggle is on (see
        // `voiceDemoModeEnabled`) — which shows off the listen → transcribe
        // → pill pipeline without needing a real agent connection.
        // Centralized here (rather than in whichever view happens to be
        // visible) so it stays correct even if the phone mockup isn't
        // currently on screen.
        Publishers.CombineLatest3($voiceReactiveEnabled, elevenLabs.$connectionState, $voiceDemoModeEnabled)
            .map { enabled, state, demo in
                (enabled && (state == .connected || demo), demo)
            }
            .removeDuplicates { $0 == $1 }
            .sink { [weak voiceConversation] shouldBeActive, demo in
                voiceConversation?.setActive(shouldBeActive, demo: demo)
            }
            .store(in: &cancellables)
    }

    @Published public var animationType: RingAnimationType = .wave

    /// Bridges in the other direction from `LEDCueParameters.animationType`
    /// (see `LEDPatternStyle.continuousAnimation`'s doc comment): `nil`
    /// (default) keeps Nexus's original behavior — a
    /// continuous loop of `animationType` above. Setting this to one of the
    /// Cue Library's canned Ziris spec-sheet behaviors (Flash, Quick Flash,
    /// Transition to Solid, Spin then Solid Fade, ...) overrides
    /// `animationType` entirely and renders that instead — see `RingView`,
    /// which renders it by handing an equivalent `LEDCueParameters` to
    /// `LEDCuePreviewView` rather than reimplementing those patterns a
    /// second time. `.continuousAnimation` itself is deliberately excluded
    /// from `ControlsView`'s picker for this (it would just mean "use
    /// `animationType`", i.e. the same thing as `nil`) but is still treated
    /// as equivalent to `nil` wherever this is read, just in case.
    @Published public var patternStyle: LEDPatternStyle? = nil
    /// Number of flashes/blinks — only meaningful when `patternStyle` is
    /// `.flash` or `.quickFlash`. Mirrors `LEDCueParameters.flashCount`.
    @Published public var flashCount: Int = 2

    /// Cycles per second. 1.0 feels like a calm "thinking" loop.
    @Published public var speed: Double = 0.6

    /// Ring stroke thickness in points.
    @Published public var lineWidth: Double = 6

    /// Diameter used in the large preview (the tab bar preview has its own fixed size).
    @Published public var previewDiameter: Double = 160

    /// Fraction of the circle (0...1) the bright arc covers in "Chasing"
    /// mode — the constant tail length in `.trailingTail` style, or the
    /// peak length reached mid-pulse in `.drawUndraw` style.
    @Published public var trailFraction: Double = 0.22
    /// How the arc behaves in "Chasing" mode — see `ChasingFillStyle`.
    @Published public var chasingFillStyle: ChasingFillStyle = .trailingTail

    /// Number of individual "diode" dots in "Alternating" mode — string-lights
    /// style, where every other diode lights up and they swap back and forth.
    @Published public var diodeCount: Double = 30
    /// Blink modulation layered under `RingAnimationType.multiChase` — see
    /// `BlinkPattern`. `.steady` (no modulation) is the default so adding
    /// this changed nothing about how anything already looked.
    /// What each diode is drawn as — see `DiodeShape`. Applies to every
    /// diode-based animation, and to everything when `diodeModeEnabled`
    /// is on.
    @Published public var diodeShape: DiodeShape = .round
    /// Diode size as a multiple of the ring's band width (`lineWidth`).
    ///
    /// 1.0 — the default — makes each diode exactly as tall as the band,
    /// so it sits flush inside it and the crop below is a no-op. That's
    /// what every preset written before this existed decodes to, so
    /// nothing already saved changes appearance.
    ///
    /// Above 1.0 the diode is taller than the band and gets trimmed by it,
    /// which is the point: real hardware shows an LED through a slot or
    /// diffuser, so you see a cropped rectangle of a larger emitter rather
    /// than the whole component.
    @Published public var diodeScale: Double = 1.0
    /// Gap between neighboring `.segment` diodes, as a fraction of each
    /// segment's own angular width. 0 makes them meet edge to edge as one
    /// continuous ring; higher values separate them into distinct wedges.
    @Published public var diodeGap: Double = 0.12
    /// Renders *any* animation as a fixed ring of diodes that stay put and
    /// simply light differently, the way addressable LED hardware
    /// actually works — rather than as continuous arcs and gradients that
    /// move.
    ///
    /// Off by default: it's a different medium, not a better one, and
    /// every saved preset predates it.
    @Published public var diodeModeEnabled: Bool = false
    @Published public var blinkPattern: BlinkPattern = .steady
    /// How fast the blink runs relative to the chase, in cycles per
    /// second. Kept separate from `speed` so the blink and the travel can
    /// be tuned against each other — a slow chase with a fast strobe is a
    /// different look from both running together.
    @Published public var blinkRate: Double = 2.0

    @Published public var primaryColor: Color = Color(red: 0.30, green: 0.62, blue: 1.0)   // cyan-blue
    @Published public var secondaryColor: Color = Color(red: 0.55, green: 0.35, blue: 0.98) // violet

    /// Extra color stops beyond Primary/Secondary, added via the "+ Add
    /// Color" button in `ColorSection` (`ControlsSections.swift`) — capped
    /// at `maxAdditionalColors` (4 more, 6 total). Kept as its own array
    /// rather than folding Primary/Secondary into one combined list, so
    /// every existing `ColorPicker` binding, preset field, and cue
    /// parameter keeps working exactly as it did before this only ever
    /// extends what's already there. `RingView.activeColors(elapsed:)` is
    /// what actually reads `[primaryColor, secondaryColor] +
    /// additionalColors` for rendering — every animation type cycles
    /// through however many colors are configured instead of a fixed pair.
    @Published public var additionalColors: [Color] = []

    /// Hard cap matching what the Controls panel's "+ Add Color" button
    /// enforces — 2 fixed slots (Primary/Secondary) plus up to this many
    /// more.
    public static let maxAdditionalColors = 4

    @Published public var glowEnabled: Bool = true
    @Published public var glowRadius: Double = 10

    /// A single "pop" knob layered on top of everything else — boosts
    /// saturation (plus a smaller amount of contrast/brightness, and the
    /// glow's own radius/intensity) across the whole composited ring,
    /// rather than needing to touch the primary/secondary colors or glow
    /// settings individually to make an animation read as punchier. On by
    /// default with a moderate boost — most animation types read noticeably
    /// flatter at neutral (1.0) than with even a modest lift.
    @Published public var vibrancyEnabled: Bool = true
    /// 1.0 = untouched. Values above that scale saturation directly, with
    /// contrast/brightness/glow riding along at a gentler fraction of the
    /// same amount — see `RingView.body`/`RingView.glow(_:color:boost:scale:)`.
    @Published public var vibrancyAmount: Double = 1.35

    // MARK: - Motion effects ("Core Animation" style extras)

    /// Timing curve applied to each rotation/cycle. Linear matches the
    /// original constant-speed behavior; the others give the motion real
    /// acceleration, or — for `.spring` — a bouncy overshoot each cycle.
    @Published public var easingStyle: EasingStyle = .linear

    /// Overshoot amount for `.spring` easing (0 = none, 1 = maximum bounce).
    @Published public var springBounce: Double = 0.35

    /// An independent "breathing" scale effect layered on top of whichever
    /// animation type is active.
    @Published public var scalePulseEnabled: Bool = false
    @Published public var scalePulseAmount: Double = 0.12
    @Published public var scalePulseSpeed: Double = 1.0

    /// When enabled, the primary/secondary colors continuously drift through
    /// the hue spectrum instead of staying fixed (secondary trails 180°
    /// behind primary, so the two stay complementary).
    @Published public var hueShiftEnabled: Bool = false
    @Published public var hueShiftSpeed: Double = 0.15

    /// Soft blur applied to the whole ring — distinct from the glow shadow,
    /// which stays sharp at the edge; this diffuses the ring itself.
    @Published public var blurRadius: Double = 0

    /// How the ring composites against whatever's behind it. `.screen` and
    /// `.plusLighter` make overlapping glow stack into a brighter, more
    /// neon look.
    @Published public var blendMode: RingBlendMode = .normal

    /// Splits the ring into red/green/blue copies, each nudged apart and
    /// screen-blended back together — a stylized, deliberately exaggerated
    /// RGB fringe rather than a subtle lens artifact, inspired by the
    /// colorful "wavelength" look of Apple's newer Siri glow.
    @Published public var chromaticAberrationEnabled: Bool = false
    /// Offset per channel, in points, before scaling.
    @Published public var chromaticAberrationAmount: Double = 6

    // MARK: - Particles
    //
    // Every knob here is a literal, unmediated CAEmitterLayer/CAEmitterCell
    // property (see RingParticleEmitter.swift) — no style presets, no
    // renamed/collapsed concepts. What's listed here is what Apple's own
    // Core Animation particle emitter API exposes.

    @Published public var particlesEnabled: Bool = false

    /// `CAEmitterLayer.emitterShape`.
    @Published public var particleEmitterShape: ParticleEmitterShape = .circle
    /// `CAEmitterLayer.emitterMode`.
    @Published public var particleEmitterMode: ParticleEmitterMode = .outline
    /// `CAEmitterLayer.emitterSize` (both dimensions), as a multiple of the
    /// ring's own diameter.
    @Published public var particleEmitterSizeMultiplier: Double = 1.0
    /// `CAEmitterLayer.renderMode`.
    @Published public var particleRenderMode: ParticleRenderMode = .unordered

    /// `CAEmitterCell.birthRate`, per color (there are 2 color cells, so
    /// total on-screen birth rate is roughly double this).
    @Published public var particleBirthRate: Double = 7
    /// `CAEmitterCell.lifetime`, in seconds. Fade is derived automatically
    /// as `alphaSpeed = -1 / lifetime`, so particles always finish fading
    /// exactly as they're removed.
    @Published public var particleLifetime: Double = 1.2
    /// `CAEmitterCell.lifetimeRange`.
    @Published public var particleLifetimeRange: Double = 0.3

    /// `CAEmitterCell.velocity`, in points/second.
    @Published public var particleVelocity: Double = 40
    /// `CAEmitterCell.velocityRange`.
    @Published public var particleVelocityRange: Double = 15

    /// `CAEmitterCell.emissionLongitude`, in degrees — the base direction
    /// particles are launched in, in the x/y plane (0 = along +x).
    @Published public var particleEmissionLongitude: Double = 0
    /// `CAEmitterCell.emissionRange`, in degrees — 0 launches every
    /// particle in exactly the same direction, 360 launches them in every
    /// direction at random.
    @Published public var particleEmissionSpread: Double = 25

    /// `CAEmitterCell.xAcceleration`, in points/second². Constant sideways
    /// force applied to every particle for its whole lifetime — e.g. wind.
    @Published public var particleXAcceleration: Double = 0
    /// `CAEmitterCell.yAcceleration`, in points/second². Positive values
    /// push particles down the screen — e.g. gravity.
    @Published public var particleYAcceleration: Double = 0

    /// `CAEmitterCell.spin`, in radians/second — rotates each particle's own
    /// image about its center. With the default soft round dot (radially
    /// symmetric) this has no visible effect; it becomes visible with a
    /// non-symmetric particle image.
    @Published public var particleSpin: Double = 0
    /// `CAEmitterCell.spinRange`.
    @Published public var particleSpinRange: Double = 0

    /// Base particle dot size in points — maps to `CAEmitterCell.scale`
    /// (converted internally against the dot bitmap's reference size).
    @Published public var particleScale: Double = 3
    /// `CAEmitterCell.scaleRange`.
    @Published public var particleScaleRange: Double = 1

    /// Optionally animates birth rate between 0 and `particleBirthRate` on
    /// a repeating cycle via a real `CABasicAnimation` on the
    /// `emitterCells.<name>.birthRate` key path — the standard Core
    /// Animation technique for a bursty/wave arrival instead of a steady
    /// trickle.
    @Published public var particlePulseEnabled: Bool = false
    /// Seconds per pulse cycle.
    @Published public var particlePulsePeriod: Double = 0.6

    /// Soft-focus applied to the whole particle layer — a real
    /// `CIGaussianBlur` in `layer.filters`, independent of the ring's own
    /// `blurRadius` (which blurs the ring + particles together, after
    /// they're composited). 0 = crisp dots.
    @Published public var particleBlurRadius: Double = 0

    // MARK: - Playback (same hold/fade/loop envelope the Cue Library uses)

    /// Off (default): the animation loops forever, as a live "thinking"
    /// indicator should. On: wraps the animation in a hold-then-fade
    /// envelope, so you can preview exactly how it'd read as a one-shot cue
    /// instead of an ambient loop.
    @Published public var sequencePlaybackEnabled: Bool = false
    /// How long the ring takes to ramp up from invisible to full opacity at
    /// the start of the envelope. Defaults to 0 — a hard cut in, which is
    /// exactly how the envelope behaved before this existed, so every saved
    /// preset and cue keeps reading the same way until it's turned up.
    @Published public var fadeInSeconds: Double = 0
    @Published public var holdSeconds: Double = 1.5
    @Published public var fadeOutSeconds: Double = 0.6
    /// 0 = repeat the hold/fade envelope forever; >0 = play that many
    /// times, then stay faded out.
    @Published public var loops: Int = 0

    // MARK: - Background image

    /// Lets you preview the ring sitting on top of real content (a
    /// screenshot of your app, a photo, etc.) instead of a flat background.
    @Published public var backgroundImageEnabled: Bool = false
    @Published public var backgroundImageData: Data? = nil
    /// 0 = no dimming, 1 = fully black — darkens the image behind the ring
    /// for contrast.
    @Published public var backgroundDimAmount: Double = 0.35

    // MARK: - Voice reactive

    /// When enabled, live amplitude adds extra glow and scale on top of
    /// whatever's already configured. The source is whichever is live —
    /// the connected ElevenLabs assistant's speech if `elevenLabs` is
    /// connected, otherwise the local microphone (see `RingView`, which
    /// picks between `elevenLabs.level` and its own `AudioLevelMonitor`
    /// each frame). Fails silently (no boost, no crash) if the mic is
    /// unavailable or permission is denied.
    @Published public var voiceReactiveEnabled: Bool = false
    @Published public var voiceReactiveSensitivity: Double = 1.0

    /// TEMPORARY demo toggle — when on (alongside "Voice reactive"), runs
    /// the listen → transcribe → pill pipeline against the local
    /// microphone only, with no ElevenLabs connection required. Lets you
    /// show off the mic listening / live waveform / speech-to-text parts
    /// without needing a working Agent ID field first. Remove once a real
    /// connection is easy to set up again.
    @Published public var voiceDemoModeEnabled: Bool = false

    /// Agent ID for the ElevenLabs Conversational AI assistant to connect
    /// to — not sensitive, kept in plain memory like everything else here.
    /// Defaulted to a real agent ID rather than left blank: with the
    /// TextField/SecureField typing bug, getting a value in here otherwise
    /// requires the clipboard-paste workaround in `ControlsView` every time
    /// the app launches fresh. Pre-filling it means Connect (below) works
    /// with zero typing or pasting — override it via the paste button if
    /// you want to point at a different agent.
    @Published public var elevenLabsAgentID: String = "agent_2001kzed7cjnf7ca4382rtnykg5y"
    /// The API key, by contrast, is a real credential — persisted to the
    /// Keychain (see `KeychainHelper`) rather than left in memory only or
    /// dropped in `UserDefaults`. Loaded once in `init()`.
    ///
    /// Deliberately *not* a `didSet` that saves on every keystroke anymore
    /// — on an ad-hoc/dev-signed build (which changes signature on every
    /// rebuild from Xcode), each `SecItemAdd` call can trigger a blocking
    /// system "wants to use your confidential information" authorization
    /// dialog, since macOS no longer recognizes the app as the same one
    /// that saved the item last time. Firing that on every character typed
    /// makes the field look like it's refusing input entirely. Call
    /// `persistElevenLabsAPIKeyToKeychain()` explicitly instead, at a
    /// point where saving actually matters — see `ControlsView`'s Connect
    /// button.
    @Published public var elevenLabsAPIKey: String = ""
    private static let elevenLabsAPIKeyAccount = "elevenlabs-api-key"

    public func persistElevenLabsAPIKeyToKeychain() {
        if elevenLabsAPIKey.isEmpty {
            KeychainHelper.delete(account: Self.elevenLabsAPIKeyAccount)
        } else {
            KeychainHelper.save(elevenLabsAPIKey, account: Self.elevenLabsAPIKeyAccount)
        }
    }

    /// The live WebSocket connection itself — a reference type held here
    /// (rather than yet another `@Published` primitive) so `ControlsView`
    /// (the Connect/Disconnect UI) and `RingView` (the live level reader)
    /// can both observe the same instance. `RingView` reads `level` fresh
    /// every animation frame via `TimelineView`, so it doesn't need
    /// `RingConfig` itself to republish `elevenLabs`'s own changes; views
    /// that aren't already redrawing every frame (like the connection
    /// status text) hold `elevenLabs` as their own `@ObservedObject`
    /// instead — see `ControlsView.init`.
    public let elevenLabs = ElevenLabsVoiceService()

    /// Hands-free "listen → send → wait for reply → listen again" loop
    /// built on top of `elevenLabs` — see `VoiceConversationController`.
    /// Started/stopped automatically by the `init()` wiring above; drives
    /// the listening/speaking pill shown above the tab bar in the phone
    /// mockup (`VoicePillView`, in the `RingAnimator` target).
    public let voiceConversation: VoiceConversationController

    // MARK: - Liquid Glass
    //
    // The real `Glass` API's own parameters — no curated intensity preset.
    // `Glass` has exactly two base styles (`.regular`/`.clear`) plus two
    // modifiers (`.tint(_:)`, `.interactive()`); this is exactly that,
    // combined into an actual `Glass` value by the `glass` computed
    // property below.

    @Published public var glassStyle: GlassStyle = .regular
    @Published public var glassTintEnabled: Bool = false
    @Published public var glassTintColor: Color = Color.black.opacity(0.35)
    /// `Glass.interactive()` — makes the material visibly react (a bounce/
    /// shimmer) to touches/clicks, the same way a `.glass`-styled button
    /// does. Applies to the tab bar capsule and ring pod here even though
    /// they're not buttons, since `.interactive()` is a real, independent
    /// `Glass` parameter, not a button-only feature.
    @Published public var glassInteractive: Bool = false
}

#if os(iOS) || os(macOS)
// The real Glass API shipped in iOS/macOS 26.0 — that's the correct
// availability tag regardless of the OS's current 27 marketing version.
@available(iOS 26.0, macOS 26.0, *)
extension RingConfig {
    /// Combines the raw `glassStyle`/`glassTintEnabled`/`glassTintColor`/
    /// `glassInteractive` properties into an actual `Glass` value to pass
    /// to `.glassEffect(_:in:)` — literally applying the real API's own
    /// parameters, in the order Apple's own modifier chain would.
    public var glass: Glass {
        var result: Glass = glassStyle == .clear ? .clear : .regular
        if glassTintEnabled {
            result = result.tint(glassTintColor)
        }
        if glassInteractive {
            result = result.interactive()
        }
        return result
    }
}
#endif
