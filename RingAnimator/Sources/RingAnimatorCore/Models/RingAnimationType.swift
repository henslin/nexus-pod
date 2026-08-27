import Foundation

/// The set of "thinking" animation patterns the ring can play.
///
/// `Sendable`: added so `RingAnimationType` can sit inside `LEDCueParameters`
/// (which is itself `Sendable`, for the same reasons `ChasingFillStyle`/
/// `EasingStyle`/etc. next to it already are) — a plain `String`-backed
/// enum with no associated values, so this is a purely additive, always-safe
/// conformance.
public enum RingAnimationType: String, CaseIterable, Identifiable, Codable, Sendable {
    case wave = "Wave"
    case chasing = "Chasing"
    case alternating = "Alternating"
    case pulse = "Pulse"
    case ripple = "Ripple"
    case wobble = "Wobble"
    case equalizer = "Equalizer"
    case dualChase = "Dual Chase"
    case sparkle = "Sparkle"
    case aurora = "Aurora"
    case liquidFill = "Liquid Fill"
    /// Discrete diodes with one travelling comet per configured color.
    ///
    /// Distinct from `.chasing` (a single continuous arc, two colors
    /// blended into a gradient) and from `.dualChase` (exactly two arcs,
    /// counter-rotating). This one is diode-based, honors `diodeCount`,
    /// and gives *every* color in the Color section its own comet, evenly
    /// spaced around the ring and all travelling the same direction — so
    /// "three colors chasing each other" is just three colors configured.
    case multiChase = "Multi Chase"

    public var id: String { rawValue }

    public var summary: String {
        switch self {
        case .wave:
            return "A smooth gradient sweeps continuously around the ring."
        case .chasing:
            return "A bright comet-like arc chases around the ring's track."
        case .alternating:
            return "String-lights: individual diodes alternate on and off around the ring."
        case .pulse:
            return "The whole ring breathes — brightness and width pulse together."
        case .ripple:
            return "Rings expand outward from the track and fade, like a sonar ping."
        case .wobble:
            return "The ring's own radius undulates around its circumference — an organic, breathing membrane."
        case .equalizer:
            return "The ring splits into segments that pulse independently, like an audio VU meter."
        case .dualChase:
            return "Two arcs chase in opposite directions, crossing as they pass."
        case .sparkle:
            return "Points around the ring flash and fade at staggered, semi-random intervals."
        case .aurora:
            return "Soft color bands drift across the ring at their own independent speeds, like an aurora curtain."
        case .liquidFill:
            return "The ring fills like rising liquid, its level slowly rising and falling with a sloshing edge."
        case .multiChase:
            return "Discrete diodes, with one comet per configured color chasing around the ring."
        }
    }
}
