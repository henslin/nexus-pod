import SwiftUI

/// Timing curve applied to each animation cycle — swaps flat, constant-speed
/// motion for something with real acceleration/deceleration, the same idea
/// Core Animation's `CAMediaTimingFunction` (and SwiftUI's `.spring()`)
/// capture for one-shot transitions, applied here to a continuously looping
/// animation instead. Since it's applied per-cycle to a value that's
/// mathematically guaranteed to start at 0 and end at 1, it composes with
/// the ever-increasing rotation phase without ever causing a visible jump.
public enum EasingStyle: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    case linear = "Linear"
    case easeIn = "Ease In"
    case easeOut = "Ease Out"
    case easeInOut = "Ease In Out"
    case spring = "Spring"

    public var id: String { rawValue }

    public var summary: String {
        switch self {
        case .linear: return "Constant speed — no acceleration."
        case .easeIn: return "Starts slow, accelerates through the cycle."
        case .easeOut: return "Starts fast, settles toward the end of the cycle."
        case .easeInOut: return "Slow to start and end, fastest through the middle."
        case .spring: return "Overshoots and settles each cycle — a bouncy rhythm."
        }
    }
}

/// How the bright arc behaves in "Chasing" mode.
public enum ChasingFillStyle: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    /// The original behavior: a fixed-length arc (`trailFraction` of the
    /// circle) continuously sweeps around, like a comet's tail.
    case trailingTail = "Trailing Tail"
    /// The classic system-spinner motion: the arc grows from a point up to
    /// `trailFraction` of the circle, then shrinks back to a point — all
    /// while continuously sweeping clockwise, never reversing. One
    /// draw-then-undraw pulse per lap.
    case drawUndraw = "Draw & Undraw"

    public var id: String { rawValue }
}

/// The physical shape drawn for each diode.
///
/// Named after the LED packages these imitate rather than the geometry:
/// real addressable rings are built from round through-hole LEDs or from
/// square/rectangular surface-mount packages, and which one a ring uses is
/// the single biggest thing separating "a glowing arc" from "a strip of
/// hardware" visually.
///
/// Square and bar diodes are rotated to sit tangent to the ring, the way a
/// component soldered to a circular board would be — axis-aligned squares
/// read as a scatter of dots rather than a ring of parts.
public enum DiodeShape: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    /// Round — through-hole LED. The original look, and the default.
    case round = "Round"
    /// Square surface-mount package.
    case square = "Square"
    /// Rectangular package, elongated along the ring's arc.
    case bar = "Bar"
    /// Equal arc segments that divide the ring itself — the donut-chart
    /// look, where each diode is a wedge of the annulus rather than a
    /// shape sitting on top of it.
    ///
    /// Structurally different from the three above: those are objects
    /// positioned on the ring's circumference, this *is* the ring, sliced.
    /// So it ignores `diodeScale` (a segment always fills the band's full
    /// thickness) and uses `diodeGap` instead to separate neighbors.
    case segment = "Segment"

    public var id: String { rawValue }

    /// Width as a multiple of the diode's height, so `.bar` can stretch
    /// along the arc while the others stay square to it.
    public var aspect: CGFloat {
        switch self {
        case .round, .square, .segment: return 1
        case .bar: return 1.9
        }
    }

    /// True for shapes that slice the ring rather than sit on it — see
    /// `.segment`. Drives which controls are relevant and which drawing
    /// path `RingView` takes.
    public var dividesTheRing: Bool { self == .segment }

    public var summary: String {
        switch self {
        case .round: return "Round through-hole LEDs."
        case .square: return "Square surface-mount packages, tangent to the ring."
        case .bar: return "Rectangular packages stretched along the ring's arc."
        case .segment: return "Equal wedges dividing the ring itself, like a donut chart."
        }
    }
}

/// Where a diode's *color* comes from.
///
/// The distinction matters more on hardware than it looks. An addressable
/// ring driver typically holds a small number of color registers and a
/// global fade — so "this LED is green because it's LED 3" and "this LED
/// is white because it's at full brightness" are different things to
/// implement, and only the second is free.
///
/// Learned from a hand-written Blender ring script that spelled it out:
/// its palette ramps sea-green → light-green → white purely by level, with
/// a note that the white core "is a strength effect, not a 3rd color", so
/// firmware can store two colors and crossfade between them. This app
/// could only assign color by index, which can't express that at all.
public enum DiodeColorMode: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    /// Each diode takes its own color from the Color section, cycling
    /// through the configured list by index. The original behavior.
    case perDiode = "Per Diode"
    /// Every diode takes its color from the palette by *brightness* —
    /// first color when dim, last when fully lit, interpolated between.
    case byLevel = "By Brightness"

    public var id: String { rawValue }

    public var summary: String {
        switch self {
        case .perDiode: return "Each diode keeps its own color from the list above."
        case .byLevel: return "Color comes from brightness — first color when dim, last at full."
        }
    }
}

/// How diodes blink underneath a chase, layered on top of whatever the
/// chase itself is doing.
///
/// Applies to `RingAnimationType.multiChase` only. The existing
/// `.alternating` type keeps its own hardcoded even/odd swap rather than
/// reading this — it *is* a blink pattern by definition, and rerouting it
/// through here would change how every saved preset using it looks.
public enum BlinkPattern: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    /// Diodes are simply lit by the chase, no modulation. The default, and
    /// what every preset saved before this existed decodes to.
    case steady = "Steady"
    /// Even and odd diodes swap on and off — the fairy-lights look
    /// `.alternating` has, but travelling with the chase.
    case alternate = "Alternate"
    /// Every diode breathes together, in step with the chase's own cycle.
    case pulse = "Pulse"
    /// Hard on/off for the whole ring, no ramp.
    case strobe = "Strobe"

    public var id: String { rawValue }

    public var summary: String {
        switch self {
        case .steady: return "No blink — diodes are lit purely by the chase."
        case .alternate: return "Even and odd diodes swap on and off as the chase travels."
        case .pulse: return "Every diode breathes together, in step with the chase."
        case .strobe: return "The whole ring cuts on and off, no ramp."
        }
    }
}

/// Blend mode for compositing the ring against whatever's behind it —
/// `.screen` / `.plusLighter` make overlapping glow stack into a brighter,
/// more saturated neon look instead of sitting flat on top of the background.
public enum RingBlendMode: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    case normal = "Normal"
    case screen = "Screen"
    case plusLighter = "Plus Lighter"
    case colorDodge = "Color Dodge"

    public var id: String { rawValue }

    public var swiftUIBlendMode: BlendMode {
        switch self {
        case .normal: return .normal
        case .screen: return .screen
        case .plusLighter: return .plusLighter
        case .colorDodge: return .colorDodge
        }
    }
}

/// `CAEmitterLayer.emitterShape` — literally Apple's own enum, mirrored
/// 1:1 (minus `.cuboid`/`.sphere`, which only matter once a layer has real
/// z-depth, which this one doesn't).
public enum ParticleEmitterShape: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    case point = "Point"
    case line = "Line"
    case rectangle = "Rectangle"
    case circle = "Circle"

    public var id: String { rawValue }
}

/// `CAEmitterLayer.emitterMode` — literally Apple's own enum, all 4 cases.
public enum ParticleEmitterMode: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    case points = "Points"
    case outline = "Outline"
    case surface = "Surface"
    case volume = "Volume"

    public var id: String { rawValue }
}

/// `CAEmitterLayer.renderMode` — literally Apple's own enum, all 5 cases.
public enum ParticleRenderMode: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    case unordered = "Unordered"
    case oldestFirst = "Oldest First"
    case oldestLast = "Oldest Last"
    case backToFront = "Back To Front"
    case additive = "Additive"

    public var id: String { rawValue }
}

/// `Glass`'s own base style — literally the two static values the real API
/// has (`Glass.regular`/`Glass.clear`), not a curated intensity preset.
/// Everything else `Glass` supports (`tint(_:)`, `interactive()`) is a
/// modifier on top of one of these two, not a third base style — see
/// `RingConfig.glass` for how the raw `glassStyle`/`glassTintEnabled`/
/// `glassTintColor`/`glassInteractive` properties combine into an actual
/// `Glass` value.
public enum GlassStyle: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    case regular = "Regular"
    case clear = "Clear"

    public var id: String { rawValue }
}

/// Shared timing-curve math so the live preview and every code exporter
/// (SwiftUI, Compose, Web) apply the exact same curve to the exact same
/// per-cycle progress value, keeping exported code visually identical to
/// what you see in the designer.
public enum MotionEasing {
    /// `t` is the fractional progress through the current cycle (0...1).
    /// `bounce` (0...1) only affects `.spring` and controls overshoot size.
    /// Guaranteed `apply(0, ...) == 0` and `apply(1, ...) ≈ 1` for every
    /// style, so chaining cycles back-to-back never produces a visible snap.
    public static func apply(_ t: Double, style: EasingStyle, bounce: Double) -> Double {
        switch style {
        case .linear:
            return t
        case .easeIn:
            return t * t
        case .easeOut:
            return 1 - (1 - t) * (1 - t)
        case .easeInOut:
            return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        case .spring:
            let decay = exp(-6 * t)
            return t + bounce * decay * sin(t * .pi * 6)
        }
    }
}
