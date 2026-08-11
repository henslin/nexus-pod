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
