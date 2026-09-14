import SwiftUI

/// One experiment in the Lab — a demonstration of one rendering technology
/// at its most flattering, in the ring's own colours.
///
/// **Why a Lab exists.** After the first RealityKit bubble came out as "a
/// lavender circle" (Chris, 2026-09-14), the question stopped being *which
/// idea* and became *what can each of these things actually do*. Nobody
/// designs well against a list of framework names. So every technology on
/// the table gets one experiment, shown large, side by side, driven by the
/// same knobs and the same audio, and the pod's future is chosen by
/// looking rather than by reading.
///
/// Each case names the technology honestly in `technology`, because that
/// is the information being bought: if the orb that looks best is a
/// fragment shader, the pod does not need a 3D engine.
public enum LabExperiment: String, CaseIterable, Identifiable, Sendable {
    case aurora
    case orb
    case bloom
    case ripple
    case mesh
    case swarm
    case sparks
    case volumetric

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .aurora:     return "Aurora"
        case .orb:        return "Orb"
        case .bloom:      return "Bloom"
        case .ripple:     return "Ripple"
        case .mesh:       return "Mesh"
        case .swarm:      return "Swarm"
        case .sparks:     return "Sparks"
        case .volumetric: return "Volumetric"
        }
    }

    /// The framework and entry point, as a tag. Short, because it sits on
    /// a list row; the full story is in `summary`.
    public var technology: String {
        switch self {
        case .aurora:     return "Metal · colorEffect"
        case .orb:        return "Metal · colorEffect"
        case .bloom:      return "Metal · layerEffect"
        case .ripple:     return "Metal · distortionEffect"
        case .mesh:       return "SwiftUI · MeshGradient"
        case .swarm:      return "SwiftUI · Canvas"
        case .sparks:     return "Core Animation · CAEmitterLayer"
        case .volumetric: return "RealityKit"
        }
    }

    public var symbol: String {
        switch self {
        case .aurora:     return "wind"
        case .orb:        return "circle.lefthalf.filled.righthalf.striped.horizontal"
        case .bloom:      return "sun.max"
        case .ripple:     return "water.waves"
        case .mesh:       return "square.grid.3x3.topleft.filled"
        case .swarm:      return "circle.dotted.circle"
        case .sparks:     return "sparkles"
        case .volumetric: return "cube.transparent"
        }
    }

    public var summary: String {
        switch self {
        case .aurora:
            return "A fragment shader colouring every pixel from a noise field that is fed through itself twice. This is the standard ‘ethereal’ construction — the warping turns blobs into flowing veils. Audio churns it rather than flashing it. Cheap enough for 120Hz at any size."
        case .orb:
            return "A sphere shaded entirely in a fragment shader: a normal from the disc, a key light, a Fresnel rim, a specular hit, and the palette swirling as if inside. No geometry. This is what the Siri orb is — a 3D-looking ball in a 2D app is usually this, not a 3D engine."
        case .bloom:
            return "The ring you already have, with a glow pass: a layerEffect samples the ring around each pixel and adds the blur back on top. Light accumulates. Every existing style gets this for free if we keep it."
        case .ripple:
            return "The ring with a distortionEffect: pixels pushed along the radius by a travelling wave. Here a beat sends a ring outward. The same entry point does refraction, heat haze, and lens wobble."
        case .mesh:
            return "Apple’s own MeshGradient, its control points moving on sine curves, clipped to a disc. Pure SwiftUI, GPU-drawn, and it looks like the iOS 18 Siri edge glow because that is roughly what it is."
        case .swarm:
            return "Twelve hundred particles orbiting the ring, drawn with SwiftUI Canvas each frame. Positions are a function of time, so there is no simulation state and nothing to keep in sync. Audio blows the orbit outward."
        case .sparks:
            return "Core Animation’s particle system, emitting from the ring’s outline. Sparks, embers, snow, smoke are all this layer with different cells. Runs on the render server, so it costs the main thread nothing. Audio drives the birth rate."
        case .volumetric:
            return "A real scene: an emissive core, a glass shell, and RealityKit’s particle emitter streaming the ring’s colours. The only experiment that is truly 3D — and the one to judge against Orb, which fakes it in a shader."
        }
    }

    /// Whether the experiment is drawn *over* the existing ring (Bloom,
    /// Ripple, Sparks) rather than replacing it. The stage draws the ring
    /// underneath for those, so the comparison is "the ring, plus this".
    public var decoratesRing: Bool {
        switch self {
        case .bloom, .ripple, .sparks: return true
        default: return false
        }
    }
}

/// The Lab's shared knobs. One object so every experiment gets the same
/// inputs and switching between them is a fair comparison, not a
/// comparison of two different settings.
@MainActor
public final class LabState: ObservableObject {
    @Published public var experiment: LabExperiment = .aurora
    /// 0…1. What "more" means is per experiment — warp for Aurora, glow
    /// for Orb, radius for Bloom — but it always means more.
    @Published public var intensity: Double = 0.5
    /// Time multiplier. 1 is the experiment's designed pace.
    @Published public var speed: Double = 1.0
    /// Feed the microphone level into the experiment.
    @Published public var audioReactive: Bool = false
    @Published public var audioSensitivity: Double = 1.5
    /// Stage backdrop. Dark is where these look best; light is where the
    /// tab bar usually is, so both matter.
    @Published public var darkStage: Bool = true
    /// Stage diameter in points.
    @Published public var diameter: Double = 360

    public init() {}
}

/// What one frame of an experiment is given. Built by the stage each
/// tick from `LabState`, the clock, and the audio monitor.
public struct LabFrame {
    public var time: Double
    public var intensity: Double
    public var audio: Double
    public var colors: [Color]
    public var diameter: CGFloat
    public var darkStage: Bool

    public init(time: Double, intensity: Double, audio: Double, colors: [Color], diameter: CGFloat, darkStage: Bool) {
        self.time = time
        self.intensity = intensity
        self.audio = audio
        self.colors = colors
        self.diameter = diameter
        self.darkStage = darkStage
    }
}
