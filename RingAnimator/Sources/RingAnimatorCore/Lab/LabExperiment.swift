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
    case refraction
    case chromatic
    case morph

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
        case .refraction: return "Refraction"
        case .chromatic:  return "Chromatic"
        case .morph:      return "Morph"
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
        case .refraction: return "Metal · layerEffect"
        case .chromatic:  return "Metal · layerEffect"
        case .morph:      return "SwiftUI · Liquid Glass"
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
        case .refraction: return "circle.circle"
        case .chromatic:  return "camera.filters"
        case .morph:      return "arrow.up.left.and.arrow.down.right.circle"
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
        case .refraction:
            return "A glass sphere over the ring, done as a layerEffect: each pixel samples the ring from where a lens would bend the light, with a Fresnel rim and a highlight. The bubble idea, without an engine — and it works over anything, including a photo."
        case .chromatic:
            return "The ring split into its red, green and blue by a radial offset, the way a cheap lens fringes. Tiny amounts read as expensive glass; large amounts on a beat read as impact."
        case .morph:
            return "Liquid Glass itself: one glass shape morphing from the pod’s circle to a pill to a sheet-sized panel and back, with the content riding inside. This is the pod-to-sheet expansion, and it is a container Apple already ships."
        }
    }

    /// Whether the experiment is drawn *over* the existing ring (Bloom,
    /// Ripple, Sparks) rather than replacing it. The stage draws the ring
    /// underneath for those, so the comparison is "the ring, plus this".
    public var decoratesRing: Bool {
        switch self {
        case .bloom, .ripple, .sparks, .refraction, .chromatic: return true
        default: return false
        }
    }

    /// The experiment's own knobs, beyond the shared ones. The panel
    /// builds a slider per entry; the experiment reads them back by id
    /// from `LabFrame.p(_:)`. Declared, not hard-wired, so adding a knob
    /// is one line here and one read in the experiment.
    public var parameters: [LabParameter] {
        switch self {
        case .aurora: return [
            .init("warp", "Warp", 0...8, 3, "Noise fed through itself. 0 is blobs, 8 is threads."),
            .init("scale", "Scale", 0.5...4, 1.7, "How many veils fit across the disc."),
            .init("octaves", "Detail", 1...6, 5, "Noise octaves. Fewer is softer and cheaper.", "%.0f"),
            .init("veil", "Veil Contrast", 0...1, 0.5, "How dark it gets between the sheets."),
            .init("rim", "Rim", 0...2, 0.9, "The lit edge."),
            .init("drift", "Colour Drift", 0...0.3, 0.03, "How fast the palette moves through the field."),
        ]
        case .orb: return [
            .init("light", "Light Angle", 0...360, 130, "Where the key light sits, degrees.", "%.0f°"),
            .init("rim", "Rim", 0...2, 0.9, "Fresnel edge — the glass look."),
            .init("spec", "Highlight", 0...1.5, 0.5, "The specular hit."),
            .init("gloss", "Gloss", 8...400, 90, "Highlight tightness.", "%.0f"),
            .init("swirl", "Swirl Scale", 0.5...6, 2.2, "Size of the pattern on the surface."),
            .init("swirlSpeed", "Swirl Speed", 0...2, 0.35, "How fast it turns."),
        ]
        case .bloom: return [
            .init("radius", "Radius", 2...80, 24, "How far the glow reaches, points.", "%.0f pt"),
            .init("strength", "Strength", 0...4, 1.4, "How much light is added."),
            .init("threshold", "Threshold", 0...1, 0, "Only pixels brighter than this bloom. 0 blooms everything."),
        ]
        case .ripple: return [
            .init("freq", "Frequency", 2...60, 18, "Rings across the radius.", "%.0f"),
            .init("waveSpeed", "Wave Speed", 0...20, 7, "How fast the rings travel."),
            .init("amp", "Amplitude", 0...30, 6, "Displacement, points.", "%.0f pt"),
            .init("falloff", "Core Hold", 0...1, 0.15, "Radius inside which nothing moves."),
        ]
        case .mesh: return [
            .init("wobble", "Wobble", 0...0.22, 0.14, "How far the control points travel."),
            .init("drift", "Colour Drift", 0...10, 2, "Hue movement across the mesh."),
            .init("glowBlur", "Glow Blur", 0...0.25, 0.08, "The halo's softness, as a fraction of size."),
            .init("glow", "Glow", 0...1, 0.55, "The halo's opacity."),
        ]
        case .swarm: return [
            .init("count", "Count", 100...4000, 1200, "Particles.", "%.0f"),
            .init("spread", "Spread", 0...1, 0.28, "How far from the ring they range."),
            .init("orbit", "Orbit Speed", 0...2, 1, "Angular speed multiplier."),
            .init("size", "Particle Size", 0.3...3, 1, "Multiplier."),
            .init("trails", "Trails", 0...1, 0, "Draws each particle's recent path."),
        ]
        case .sparks: return [
            .init("rate", "Birth Rate", 0...2000, 300, "Sparks per second.", "%.0f"),
            .init("velocity", "Velocity", 0...300, 60, "Points per second.", "%.0f"),
            .init("life", "Lifetime", 0.2...5, 1.6, "Seconds.", "%.1f s"),
            .init("size", "Size", 0.02...0.4, 0.12, "Sprite scale."),
            .init("spin", "Spin", 0...10, 0, "Radians per second."),
            .init("inward", "Inward", 0...1, 0, "0 emits outward, 1 pulls sparks into the ring."),
        ]
        case .volumetric: return [
            .init("core", "Core Size", 0.1...0.7, 0.34, "Radius as a fraction of the shell."),
            .init("satellites", "Satellites", 0...8, 3, "Orbiting bodies.", "%.0f"),
            .init("orbit", "Orbit Speed", 0...3, 1, "Multiplier."),
            .init("rate", "Motes", 0...2000, 500, "Particles per second.", "%.0f"),
            .init("moteSpeed", "Mote Speed", 0...0.3, 0.1, "Units per second."),
            .init("spin", "Spin", 0...1, 0.15, "The whole scene's turn, radians per second."),
            .init("glass", "Glass", 0...0.4, 0.06, "Shell opacity. Past 0.15 it goes milky."),
        ]
        case .refraction: return [
            .init("ior", "Refraction", 0...1, 0.5, "How much the lens bends what is under it."),
            .init("lens", "Lens Size", 0.3...1, 0.75, "Diameter as a fraction of the stage."),
            .init("rim", "Rim", 0...2, 0.8, "Fresnel edge."),
            .init("spec", "Highlight", 0...1.5, 0.6, "The specular hit."),
            .init("drift", "Drift", 0...1, 0.3, "The lens wanders on a slow orbit."),
        ]
        case .chromatic: return [
            .init("split", "Split", 0...30, 4, "Channel offset at the rim, points.", "%.0f pt"),
            .init("radial", "Radial", 0...1, 1, "1 offsets outward from the centre; 0 offsets sideways."),
            .init("beat", "Beat", 0...40, 20, "Extra split on audio, points.", "%.0f pt"),
        ]
        case .morph: return [
            .init("hold", "Hold", 0.5...6, 2, "Seconds in each state.", "%.1f s"),
            .init("stages", "Stages", 1...3, 3, "1 circle↔pill, 2 adds a card, 3 adds the sheet.", "%.0f"),
            .init("spring", "Spring", 0.2...1.2, 0.55, "Response — lower is snappier."),
            .init("bounce", "Bounce", 0...1, 0.2, "Damping headroom."),
        ]
        }
    }
}

/// One knob on one experiment.
public struct LabParameter: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let range: ClosedRange<Double>
    public let defaultValue: Double
    public let help: String
    public let format: String

    public init(_ id: String, _ name: String, _ range: ClosedRange<Double>, _ defaultValue: Double, _ help: String, _ format: String = "%.2f") {
        self.id = id
        self.name = name
        self.range = range
        self.defaultValue = defaultValue
        self.help = help
        self.format = format
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
    /// Per-experiment knob values, keyed `experiment.param`. Absent means
    /// the parameter's default.
    @Published public var values: [String: Double] = [:]

    public init() {}

    public func value(_ parameter: LabParameter, of experiment: LabExperiment) -> Double {
        values["\(experiment.id).\(parameter.id)"] ?? parameter.defaultValue
    }

    public func binding(_ parameter: LabParameter, of experiment: LabExperiment) -> Binding<Double> {
        Binding(
            get: { self.value(parameter, of: experiment) },
            set: { self.values["\(experiment.id).\(parameter.id)"] = $0 })
    }

    public func resetParameters(of experiment: LabExperiment) {
        for p in experiment.parameters { values.removeValue(forKey: "\(experiment.id).\(p.id)") }
    }

    /// The current experiment's knobs, resolved, for a `LabFrame`.
    public func resolvedParameters(of experiment: LabExperiment) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: experiment.parameters.map { ($0.id, value($0, of: experiment)) })
    }
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
    /// The experiment's own knobs — see `LabExperiment.parameters`.
    public var params: [String: Double]

    public init(time: Double, intensity: Double, audio: Double, colors: [Color], diameter: CGFloat, darkStage: Bool, params: [String: Double] = [:]) {
        self.time = time
        self.intensity = intensity
        self.audio = audio
        self.colors = colors
        self.diameter = diameter
        self.darkStage = darkStage
        self.params = params
    }

    /// A knob's value, or its declared default when the frame was built
    /// without one (a harness, a thumbnail).
    public func p(_ id: String, _ experiment: LabExperiment) -> Double {
        params[id] ?? experiment.parameters.first { $0.id == id }?.defaultValue ?? 0
    }
}
