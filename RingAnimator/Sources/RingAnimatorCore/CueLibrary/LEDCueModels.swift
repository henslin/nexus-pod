import SwiftUI

/// The shape of the LED behavior for a given cue. This is a small, closed
/// set of "pattern families" that every row in the Ziris cue sheet maps to —
/// the actual look for a given cue comes from combining a style with
/// `LEDCueParameters` (colors, speed, counts, timings).
public enum LEDPatternStyle: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    /// Bridges to the full Nexus animation system — `speed`,
    /// `animationType` (all 11 continuous "AI thinking" variants: Wave,
    /// Chasing, Alternating, ...), `lineWidth`, `trailFraction`/
    /// `chasingFillStyle`, `diodeCount`, and every motion/glow/vibrancy/
    /// particle knob below all apply, exactly as they would in Nexus
    /// — see `LEDCuePreviewView`, which literally renders this
    /// case by handing an equivalent `RingConfig` to `RingView` rather than
    /// reimplementing the animation a second time. Every other case below
    /// stays a small, purpose-built rendering of one named Ziris spec-sheet
    /// behavior instead.
    case continuousAnimation
    case solid              // steady, unblinking color
    case off                // ring fully off
    case flash               // slow on/off blink, repeating or looped
    case quickFlash          // fast on/off blink (urgent/error feel)
    case ripple               // outward pulse/ripple from a point or center

    // MARK: - Primitives
    //
    // One behavior each, looping for as long as the step lasts — nothing
    // built in about settling or fading. These are the pieces the
    // composites below were always made of; they exist separately now that
    // `RingTimeline` can sequence steps, so "spin, then go solid, then
    // fade" is three steps you arrange rather than one case someone had to
    // hardcode. Prefer these when building something new.

    /// A single bright arc travelling around the ring, once per
    /// `1 / speed` seconds.
    ///
    /// That rate is load-bearing, not incidental: `SegmentLength.rotations`
    /// converts a step's length using `rotations = seconds × speed`, so a
    /// spin primitive turning at any other rate would make "spin exactly
    /// three times" quietly untrue. Don't retune this to taste — retune
    /// `speed`.
    case spin
    /// A breathing pulse whose rate accelerates, giving a countdown feel.
    /// Restarts its ramp every `2.2` seconds.
    case pulseAccelerate
    /// A hue sweep through the full color wheel, once per `1 / speed`
    /// seconds. Ignores the configured colors by definition.
    case rainbow

    // MARK: - Composites (spec-sheet behaviors)
    //
    // Multi-phase behaviors transcribed from the Ziris cue sheet, each one
    // a primitive above followed by a solid hold and a fade. Kept because
    // the cue library's rows reference them as ground truth and saved cue
    // JSON decodes by these exact names — but they're no longer where new
    // work should start. Their renderers now delegate to the primitives
    // rather than reimplementing them, so the two can't drift.

    case transitionToSolid    // brief animation that settles into a solid color
    case spinThenSolidFade    // a spinner/chase that resolves into a solid fade-out
    case pulseAccelerateThenSolidFade // breathing pulse that speeds up, then fades to solid
    case rainbowThenWhiteFade // multicolor sweep that resolves to white, then fades
    case earConOnly            // sound only, no LED change (ring stays as-is / off)
    case notApplicable         // no LED behavior defined yet (future/placeholder cue)
    case voiceAssistantColor   // uses the platform voice-assistant's standard color cue
    case custom                // anything bespoke — see `notes` for a text description

    public var id: String { rawValue }

    /// True for the multi-phase spec-sheet behaviors — a primitive
    /// followed by a solid hold and a fade, all baked into one case.
    ///
    /// Used to group them apart in the Pattern Style picker so the
    /// primitives read as the default way to build something and these
    /// read as what they are: canned sequences kept for the cue library.
    /// Anything one of these does can be built as timeline steps, with the
    /// hold and fade as their own steps instead of hidden parameters.
    public var isComposite: Bool {
        switch self {
        case .transitionToSolid, .spinThenSolidFade,
             .pulseAccelerateThenSolidFade, .rainbowThenWhiteFade:
            return true
        default:
            return false
        }
    }

    public var displayName: String {
        switch self {
        case .continuousAnimation: return "Continuous Animation (Nexus)"
        case .solid: return "Solid"
        case .off: return "Off"
        case .flash: return "Flash"
        case .quickFlash: return "Quick Flash"
        case .ripple: return "Ripple"
        case .spin: return "Spin"
        case .pulseAccelerate: return "Pulse (Accelerating)"
        case .rainbow: return "Rainbow"
        case .transitionToSolid: return "Transition to Solid"
        case .spinThenSolidFade: return "Spin, then Solid Fade"
        case .pulseAccelerateThenSolidFade: return "Pulse (Accelerating), then Fade"
        case .rainbowThenWhiteFade: return "Rainbow, then White Fade"
        case .earConOnly: return "Earcon Only (no LED)"
        case .notApplicable: return "N/A (future / undefined)"
        case .voiceAssistantColor: return "Voice Assistant Color"
        case .custom: return "Custom"
        }
    }
}

/// Every tunable knob for a single cue's LED behavior. `Codable` +
/// `Equatable` so it round-trips to JSON for persistence/export and so the
/// store can tell when a cue has been tweaked away from its default.
public struct LEDCueParameters: Codable, Equatable, Sendable {
    public var style: LEDPatternStyle
    public var primaryColorHex: String
    public var secondaryColorHex: String
    /// Cycles per second / animation speed. Meaning depends on `style`.
    public var speed: Double
    /// Number of flashes/blinks for finite patterns (e.g. Wi-Fi connected = 2 flashes).
    public var flashCount: Int
    /// How long the pattern holds at full/solid before fading or looping, in seconds.
    public var holdSeconds: Double
    /// How long the fade-out takes, in seconds. 0 = no fade, ring cuts off.
    public var fadeOutSeconds: Double
    /// Number of times the whole pattern repeats. 0 = loops forever until state changes.
    public var loops: Int
    /// Free-text notes — used to capture nuance from the spec sheet that
    /// doesn't fit cleanly into the structured fields, and as the primary
    /// description for `.custom` and `.notApplicable` cues.
    public var notes: String

    // MARK: - Continuous animation (only meaningful when `style ==
    // .continuousAnimation` — see that case's doc comment). Kept as regular
    // top-level fields, defaulted so every existing cue in the library
    // keeps behaving exactly as before, the same reasoning as every other
    // section here.

    /// Which of Nexus's 11 continuous "AI thinking" animations
    /// to render — see `RingAnimationType`.
    public var animationType: RingAnimationType
    /// Ring stroke thickness in points — `RingConfig.lineWidth`'s
    /// equivalent (the rest of this file's style renderers take their own
    /// `lineWidth` as a separate `LEDCuePreviewView` init parameter instead,
    /// since it's meant to vary with the surrounding chrome size, not the
    /// cue itself).
    public var lineWidth: Double
    /// Fraction of the circle (0...1) the bright arc covers in "Chasing"/
    /// "Dual Chase" — see `RingConfig.trailFraction`.
    public var trailFraction: Double
    /// See `RingConfig.chasingFillStyle`.
    public var chasingFillStyle: ChasingFillStyle
    /// Dot/segment count for "Alternating"/"Equalizer"/"Sparkle"/"Multi
    /// Chase" — see `RingConfig.diodeCount`.
    public var diodeCount: Double
    /// Blink modulation for "Multi Chase" — see `BlinkPattern`. Optional
    /// for the same decoding reason as `RingPreset.blinkPattern`: saved
    /// cue JSON written before this existed has no such key, and
    /// synthesized `Decodable` would throw rather than default it.
    public var diodeShape: DiodeShape?
    public var diodeScale: Double?
    public var diodeModeEnabled: Bool?
    public var blinkPattern: BlinkPattern?
    public var blinkRate: Double?

    // MARK: - Motion effects (same knobs as Nexus)
    // Defaulted so every existing cue in the library keeps behaving exactly
    // as before without needing to be touched.

    public var easingStyle: EasingStyle
    public var springBounce: Double
    public var scalePulseEnabled: Bool
    public var scalePulseAmount: Double
    public var scalePulseSpeed: Double
    public var hueShiftEnabled: Bool
    public var hueShiftSpeed: Double
    public var blurRadius: Double
    public var blendMode: RingBlendMode
    public var chromaticAberrationEnabled: Bool
    public var chromaticAberrationAmount: Double

    // MARK: - Glow & vibrancy (same knobs as Nexus's "Glow &
    // Blend" section — see `RingConfig.glowEnabled`/`vibrancyEnabled`).
    // Applied universally (every `style` above respects these now, not just
    // `.continuousAnimation`) — see `LEDCuePreviewView.ring(...)`.

    public var glowEnabled: Bool
    public var glowRadius: Double
    public var vibrancyEnabled: Bool
    public var vibrancyAmount: Double

    // MARK: - Particles (same raw CAEmitterLayer/CAEmitterCell controls as
    // Nexus — see RingConfig.swift for the full explanation of
    // each property).

    public var particlesEnabled: Bool
    public var particleEmitterShape: ParticleEmitterShape
    public var particleEmitterMode: ParticleEmitterMode
    public var particleEmitterSizeMultiplier: Double
    public var particleRenderMode: ParticleRenderMode
    public var particleBirthRate: Double
    public var particleLifetime: Double
    public var particleLifetimeRange: Double
    public var particleVelocity: Double
    public var particleVelocityRange: Double
    public var particleEmissionLongitude: Double
    public var particleEmissionSpread: Double
    public var particleXAcceleration: Double
    public var particleYAcceleration: Double
    public var particleSpin: Double
    public var particleSpinRange: Double
    public var particleScale: Double
    public var particleScaleRange: Double
    public var particlePulseEnabled: Bool
    public var particlePulsePeriod: Double
    public var particleBlurRadius: Double

    public init(
        style: LEDPatternStyle,
        primaryColorHex: String = LEDCueColors.white,
        secondaryColorHex: String = LEDCueColors.white,
        speed: Double = 1.0,
        flashCount: Int = 0,
        holdSeconds: Double = 1.5,
        fadeOutSeconds: Double = 0.6,
        loops: Int = 0,
        notes: String = "",
        animationType: RingAnimationType = .wave,
        lineWidth: Double = 12,
        trailFraction: Double = 0.22,
        chasingFillStyle: ChasingFillStyle = .trailingTail,
        diodeCount: Double = 30,
        diodeShape: DiodeShape? = nil,
        diodeScale: Double? = nil,
        diodeModeEnabled: Bool? = nil,
        blinkPattern: BlinkPattern? = nil,
        blinkRate: Double? = nil,
        easingStyle: EasingStyle = .linear,
        springBounce: Double = 0.35,
        scalePulseEnabled: Bool = false,
        scalePulseAmount: Double = 0.12,
        scalePulseSpeed: Double = 1.0,
        hueShiftEnabled: Bool = false,
        hueShiftSpeed: Double = 0.15,
        blurRadius: Double = 0,
        blendMode: RingBlendMode = .normal,
        chromaticAberrationEnabled: Bool = false,
        chromaticAberrationAmount: Double = 6,
        glowEnabled: Bool = true,
        glowRadius: Double = 10,
        vibrancyEnabled: Bool = true,
        vibrancyAmount: Double = 1.35,
        particlesEnabled: Bool = false,
        particleEmitterShape: ParticleEmitterShape = .circle,
        particleEmitterMode: ParticleEmitterMode = .outline,
        particleEmitterSizeMultiplier: Double = 1.0,
        particleRenderMode: ParticleRenderMode = .unordered,
        particleBirthRate: Double = 7,
        particleLifetime: Double = 1.2,
        particleLifetimeRange: Double = 0.3,
        particleVelocity: Double = 40,
        particleVelocityRange: Double = 15,
        particleEmissionLongitude: Double = 0,
        particleEmissionSpread: Double = 25,
        particleXAcceleration: Double = 0,
        particleYAcceleration: Double = 0,
        particleSpin: Double = 0,
        particleSpinRange: Double = 0,
        particleScale: Double = 3,
        particleScaleRange: Double = 1,
        particlePulseEnabled: Bool = false,
        particlePulsePeriod: Double = 0.6,
        particleBlurRadius: Double = 0
    ) {
        self.style = style
        self.primaryColorHex = primaryColorHex
        self.secondaryColorHex = secondaryColorHex
        self.speed = speed
        self.flashCount = flashCount
        self.holdSeconds = holdSeconds
        self.fadeOutSeconds = fadeOutSeconds
        self.loops = loops
        self.notes = notes
        self.animationType = animationType
        self.lineWidth = lineWidth
        self.trailFraction = trailFraction
        self.chasingFillStyle = chasingFillStyle
        self.diodeCount = diodeCount
        self.diodeShape = diodeShape
        self.diodeScale = diodeScale
        self.diodeModeEnabled = diodeModeEnabled
        self.blinkPattern = blinkPattern
        self.blinkRate = blinkRate
        self.easingStyle = easingStyle
        self.springBounce = springBounce
        self.scalePulseEnabled = scalePulseEnabled
        self.scalePulseAmount = scalePulseAmount
        self.scalePulseSpeed = scalePulseSpeed
        self.hueShiftEnabled = hueShiftEnabled
        self.hueShiftSpeed = hueShiftSpeed
        self.blurRadius = blurRadius
        self.blendMode = blendMode
        self.chromaticAberrationEnabled = chromaticAberrationEnabled
        self.chromaticAberrationAmount = chromaticAberrationAmount
        self.glowEnabled = glowEnabled
        self.glowRadius = glowRadius
        self.vibrancyEnabled = vibrancyEnabled
        self.vibrancyAmount = vibrancyAmount
        self.particlesEnabled = particlesEnabled
        self.particleEmitterShape = particleEmitterShape
        self.particleEmitterMode = particleEmitterMode
        self.particleEmitterSizeMultiplier = particleEmitterSizeMultiplier
        self.particleRenderMode = particleRenderMode
        self.particleBirthRate = particleBirthRate
        self.particleLifetime = particleLifetime
        self.particleLifetimeRange = particleLifetimeRange
        self.particleVelocity = particleVelocity
        self.particleVelocityRange = particleVelocityRange
        self.particleEmissionLongitude = particleEmissionLongitude
        self.particleEmissionSpread = particleEmissionSpread
        self.particleXAcceleration = particleXAcceleration
        self.particleYAcceleration = particleYAcceleration
        self.particleSpin = particleSpin
        self.particleSpinRange = particleSpinRange
        self.particleScale = particleScale
        self.particleScaleRange = particleScaleRange
        self.particlePulseEnabled = particlePulseEnabled
        self.particlePulsePeriod = particlePulsePeriod
        self.particleBlurRadius = particleBlurRadius
    }
}

/// One row from the Ziris LED cue specification sheet, with a default set
/// of parameters transcribed from the "Ziris" behavior column.
public struct LEDCue: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var category: String
    public var subcategory: String?
    public var name: String
    /// The original free-text description from the spec sheet, kept as
    /// ground truth / reference alongside the structured defaults.
    public var specText: String
    public var defaultParameters: LEDCueParameters

    public init(
        id: String,
        category: String,
        subcategory: String? = nil,
        name: String,
        specText: String,
        defaultParameters: LEDCueParameters
    ) {
        self.id = id
        self.category = category
        self.subcategory = subcategory
        self.name = name
        self.specText = specText
        self.defaultParameters = defaultParameters
    }
}

/// Shared hex color constants used across the default cue dataset, so the
/// palette stays consistent and easy to re-tune in one place.
public enum LEDCueColors {
    public static let white = "#FFFFFF"
    public static let green = "#30D158"
    public static let red = "#FF3B30"
    public static let amber = "#FFB000"
    public static let blue = "#0A84FF"
    public static let purple = "#AF52DE"
    public static let off = "#000000"
}
