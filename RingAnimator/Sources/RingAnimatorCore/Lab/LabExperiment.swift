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
    case liquid
    case rays
    case sphere

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
        case .liquid:     return "Liquid"
        case .rays:       return "Rays"
        case .sphere:     return "Sphere"
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
        case .liquid:     return "Metal · colorEffect"
        case .rays:       return "Metal · layerEffect"
        case .sphere:     return "Metal · colorEffect"
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
        case .liquid:     return "drop.circle"
        case .rays:       return "rays"
        case .sphere:     return "circle.hexagongrid"
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
        case .liquid:
            return "Metaballs: a handful of blobs orbiting inside the disc, drawn as one distance field so they merge and split like mercury. Each blob carries a palette colour; where they meet, the colours blend. Audio pulls them apart."
        case .rays:
            return "Light streaks: a layerEffect that samples the ring along the line back to the centre and accumulates — a radial blur, added. Gives the ring god-rays. Over Bloom it’s a sun; over Sparks it’s a fire."
        case .sphere:
            return "The After Effects gradient-sphere recipe as one shader: a small gradient shape, box-blurred, pushed around by turbulent displace, wrapped by a lens into a sphere with a thin bright rim. Add Bloom from the post stack for his Deep Glow. Every stage has his controls."
        }
    }

    /// Whether the experiment is drawn *over* the existing ring (Bloom,
    /// Ripple, Sparks) rather than replacing it. The stage draws the ring
    /// underneath for those, so the comparison is "the ring, plus this".
    public var decoratesRing: Bool {
        switch self {
        case .bloom, .ripple, .sparks, .refraction, .chromatic, .rays: return true
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
            .init("strength", "Strength", 0...4, 1.0, "How much light is added. Full-disc bases want less than a ring."),
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
        case .liquid: return [
            .init("blobs", "Blobs", 2...8, 5, "How many.", "%.0f"),
            .init("size", "Blob Size", 0.1...0.6, 0.32, "Radius as a fraction of the disc."),
            .init("goo", "Goo", 0.02...0.4, 0.14, "How far apart they still merge."),
            .init("orbit", "Orbit", 0...2, 0.6, "How fast they wander."),
            .init("edge", "Edge", 0...1, 0.8, "Sharpness of the surface. 0 is a cloud."),
            .init("shade", "Shade", 0...1, 0.5, "Sphere shading on the surface."),
        ]
        case .rays: return [
            .init("length", "Length", 0...1, 0.5, "How far the streaks reach, as a fraction of the radius."),
            .init("strength", "Strength", 0...3, 1, "How much light the streaks add."),
            .init("decay", "Decay", 0.5...1, 0.92, "How quickly a streak fades along its length."),
            .init("twist", "Twist", -1...1, 0, "Curves the streaks. 0 is straight out."),
        ]
        case .sphere: return [
            .init("shape", "Shape", 0...2, 0, "0 star, 1 blob, 2 ring.", "%.0f"),
            .init("srcSize", "Source Size", 0.1...1.2, 0.45, "The gradient shape's radius."),
            .init("blur", "Blur", 0...1, 0.35, "Fast Box Blur — softens the shape's edge."),
            .init("dispAmount", "Displace Amount", 0...2, 0.9, "Turbulent Displace amount."),
            .init("dispSize", "Displace Size", 0.3...6, 1.6, "Turbulent Displace size — bigger is smoother."),
            .init("complexity", "Complexity", 1...5, 2, "Noise octaves.", "%.0f"),
            .init("evolution", "Evolution", 0...3, 1, "How fast the turbulence evolves."),
            .init("wiggle", "Wiggle", 0...1, 0.5, "The source wanders."),
            .init("curvature", "Curvature", -1...1, 0.7, "The lens. Positive pinches to the rim, negative bulges."),
            .init("rim", "Rim", 0...2, 1, "The thin bright edge."),
            .init("exposure", "Exposure", 0...3, 1.2, "Source brightness."),
        ]
        }
    }
}

/// Which audio signal an experiment listens to.
public enum LabAudioSource: String, CaseIterable, Identifiable, Sendable {
    case level, bass, mid, treble, beat
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .level:  return "Level"
        case .bass:   return "Bass"
        case .mid:    return "Mid"
        case .treble: return "Treble"
        case .beat:   return "Beat"
        }
    }
}

/// The four smoothed signals plus the beat, as a frame sees them.
public struct LabAudioBands: Sendable {
    public var level: Double = 0
    public var bass: Double = 0
    public var mid: Double = 0
    public var treble: Double = 0
    public var beat: Double = 0
    public init() {}
    public func value(_ source: LabAudioSource) -> Double {
        switch source {
        case .level: return level
        case .bass: return bass
        case .mid: return mid
        case .treble: return treble
        case .beat: return beat
        }
    }
}

/// A palette for the Lab — the Nexus animation's own colours, or one of
/// a few curated sets, so an experiment can be judged in colours it was
/// not designed around.
public enum LabPalette: String, CaseIterable, Identifiable, Sendable {
    case nexus, aurora, ember, ice, candy, mono, spectrum
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .nexus:    return "Nexus"
        case .aurora:   return "Aurora"
        case .ember:    return "Ember"
        case .ice:      return "Ice"
        case .candy:    return "Candy"
        case .mono:     return "Mono"
        case .spectrum: return "Spectrum"
        }
    }
    /// `nil` for `.nexus` — the caller substitutes the config's colours.
    public var colors: [Color]? {
        switch self {
        case .nexus:    return nil
        case .aurora:   return [Color(hex: "#16E0A0"), Color(hex: "#2A7BFF"), Color(hex: "#9B4DFF")]
        case .ember:    return [Color(hex: "#FF3B1F"), Color(hex: "#FF9A1F"), Color(hex: "#FFE066")]
        case .ice:      return [Color(hex: "#DFF6FF"), Color(hex: "#6BC5FF"), Color(hex: "#1E5BFF")]
        case .candy:    return [Color(hex: "#FF4FA3"), Color(hex: "#FFB03B"), Color(hex: "#7CFFCB")]
        case .mono:     return [Color(hex: "#FFFFFF"), Color(hex: "#7A7A7A")]
        case .spectrum: return [Color(hex: "#FF3B30"), Color(hex: "#FFCC00"), Color(hex: "#34C759"), Color(hex: "#007AFF"), Color(hex: "#AF52DE")]
        }
    }
}

/// A post effect: one of the ring-decorating experiments, applied over
/// whatever the base experiment drew. The stack is what turns "eleven
/// demos" into a design space — Aurora with Bloom and a little
/// Chromatic is a different thing from any of the three alone.
public enum LabPostEffect: String, CaseIterable, Identifiable, Sendable {
    case bloom, rays, ripple, refraction, chromatic
    public var id: String { rawValue }
    /// The experiment whose knobs this effect uses.
    public var experiment: LabExperiment {
        switch self {
        case .bloom: return .bloom
        case .rays: return .rays
        case .ripple: return .ripple
        case .refraction: return .refraction
        case .chromatic: return .chromatic
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
    /// Which signal `LabFrame.audio` carries.
    @Published public var audioSource: LabAudioSource = .level
    @Published public var audioAttack: Double = 0.03
    @Published public var audioRelease: Double = 0.25
    @Published public var palette: LabPalette = .nexus
    /// Post effects, in the order they are applied.
    @Published public var post: [LabPostEffect] = []
    /// Show the experiment at pod size in a glass pod, in the corner.
    @Published public var showPod: Bool = true
    /// An SF Symbol drawn inside Orb, Refraction and Liquid — the glyph
    /// state of the pod, inside the effect. Empty for none.
    @Published public var glyph: String = ""
    /// Continuous hue rotation of the palette, degrees per second.
    @Published public var hueDrift: Double = 0

    public init() {}

    public func togglePost(_ effect: LabPostEffect) {
        if let i = post.firstIndex(of: effect) { post.remove(at: i) } else { post.append(effect) }
    }

    /// Every experiment's knobs, resolved — the base and the post stack
    /// each read their own by experiment.
    public func allResolvedParameters() -> [String: Double] {
        var out: [String: Double] = [:]
        for e in LabExperiment.allCases {
            for p in e.parameters { out["\(e.id).\(p.id)"] = value(p, of: e) }
        }
        return out
    }

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
    /// Every experiment's knobs, keyed `experiment.param` — the base and
    /// each post effect read their own. See `LabExperiment.parameters`.
    public var params: [String: Double]
    /// The full spectrum, for experiments that want more than `audio`.
    public var bands: LabAudioBands
    /// An SF Symbol to draw inside, or `nil`.
    public var glyph: String?

    public init(time: Double, intensity: Double, audio: Double, colors: [Color], diameter: CGFloat, darkStage: Bool,
                params: [String: Double] = [:], bands: LabAudioBands = LabAudioBands(), glyph: String? = nil) {
        self.time = time
        self.intensity = intensity
        self.audio = audio
        self.colors = colors
        self.diameter = diameter
        self.darkStage = darkStage
        self.params = params
        self.bands = bands
        self.glyph = glyph
    }

    /// A knob's value, or its declared default when the frame was built
    /// without one (a harness, a thumbnail).
    public func p(_ id: String, _ experiment: LabExperiment) -> Double {
        params["\(experiment.id).\(id)"] ?? experiment.parameters.first { $0.id == id }?.defaultValue ?? 0
    }

    /// The same frame at another size — for the pod-size preview.
    public func resized(_ d: CGFloat) -> LabFrame {
        var f = self
        f.diameter = d
        return f
    }
}
