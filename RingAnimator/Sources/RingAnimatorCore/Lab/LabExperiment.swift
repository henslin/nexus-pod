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
    case tunnel
    case constellation
    case harmonograph
    case ink
    case lightning
    case cells
    case warp
    case burst
    case symbols
    case shapeshift
    case lattice
    case stipple
    case bubble
    case slices
    case vessel
    case stack
    case cascade
    case prism
    case holo
    case lenticular
    case moire
    case orrery
    case bokeh
    // Post effects with no base of their own.
    case kaleido
    case dots
    case grain
    case glitch
    case crt
    case neon
    case frost
    case duotone
    case spin
    case tiles
    case chrome
    // Flows — the tap-on-Nexus question, on a phone canvas.
    case journey
    case agentStates
    case waveform
    case edgeGlow
    case caption

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
        case .tunnel:     return "Tunnel"
        case .constellation: return "Constellation"
        case .harmonograph: return "Harmonograph"
        case .ink:        return "Ink"
        case .lightning:  return "Lightning"
        case .cells:      return "Cells"
        case .warp:       return "Warp"
        case .burst:      return "Burst"
        case .symbols:    return "Symbols"
        case .shapeshift: return "Shapeshift"
        case .lattice:    return "Lattice"
        case .stipple:    return "Stipple"
        case .tiles:      return "Tiles"
        case .bubble:     return "Bubble"
        case .slices:     return "Slices"
        case .vessel:     return "Vessel"
        case .stack:      return "Stack"
        case .cascade:    return "Cascade"
        case .prism:      return "Prism"
        case .chrome:     return "Chrome"
        case .holo:       return "Holo"
        case .lenticular: return "Lenticular"
        case .moire:      return "Moiré"
        case .orrery:     return "Orrery"
        case .bokeh:      return "Bokeh"
        case .kaleido:    return "Kaleido"
        case .dots:       return "Dots"
        case .grain:      return "Grain"
        case .glitch:     return "Glitch"
        case .crt:        return "CRT"
        case .neon:       return "Neon"
        case .frost:      return "Frost"
        case .duotone:    return "Duotone"
        case .spin:       return "Spin"
        case .journey:    return "Journey"
        case .agentStates: return "Agent States"
        case .waveform:   return "Waveform"
        case .edgeGlow:   return "Edge Glow"
        case .caption:    return "Caption"
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
        case .tunnel:     return "Metal · colorEffect"
        case .constellation: return "SwiftUI · Canvas"
        case .harmonograph: return "SwiftUI · Canvas"
        case .ink:        return "Metal · compute + MTKView"
        case .lightning:  return "SwiftUI · Canvas"
        case .cells:      return "Metal · colorEffect"
        case .warp:       return "SwiftUI · Canvas"
        case .burst:      return "SwiftUI · Canvas, on tap"
        case .symbols:    return "SwiftUI · SF Symbol effects"
        case .shapeshift: return "Metal · colorEffect (SDF)"
        case .lattice:    return "SwiftUI · Canvas"
        case .stipple:    return "SwiftUI · Canvas"
        case .tiles:      return "Metal · layerEffect"
        case .bubble:     return "Metal · colorEffect"
        case .slices:     return "Metal · colorEffect"
        case .vessel:     return "Metal · colorEffect (SDF)"
        case .stack:      return "SwiftUI · Canvas"
        case .cascade:    return "SwiftUI · Canvas"
        case .prism:      return "SwiftUI · Canvas"
        case .chrome:     return "Metal · layerEffect"
        case .holo:       return "Metal · colorEffect"
        case .lenticular: return "Metal · colorEffect"
        case .moire:      return "Metal · colorEffect"
        case .orrery:     return "SwiftUI · Canvas"
        case .bokeh:      return "SwiftUI · Canvas"
        case .kaleido:    return "Metal · layerEffect"
        case .dots:       return "Metal · layerEffect"
        case .grain:      return "Metal · layerEffect"
        case .glitch:     return "Metal · layerEffect"
        case .crt:        return "Metal · layerEffect"
        case .neon:       return "Metal · layerEffect"
        case .frost:      return "Metal · layerEffect"
        case .duotone:    return "Metal · layerEffect"
        case .spin:       return "Metal · layerEffect"
        case .journey:    return "SwiftUI · Liquid Glass + springs"
        case .agentStates: return "SwiftUI · state machine"
        case .waveform:   return "SwiftUI · Canvas"
        case .edgeGlow:   return "SwiftUI · blur + gradient"
        case .caption:    return "SwiftUI · text transitions"
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
        case .tunnel:     return "circle.circle.fill"
        case .constellation: return "point.3.connected.trianglepath.dotted"
        case .harmonograph: return "scribble.variable"
        case .ink:        return "drop.fill"
        case .lightning:  return "bolt.fill"
        case .cells:      return "hexagon.fill"
        case .warp:       return "sparkle"
        case .burst:      return "fireworks"
        case .symbols:    return "star.circle"
        case .shapeshift: return "square.on.circle"
        case .lattice:    return "globe"
        case .stipple:    return "circle.dotted"
        case .tiles:      return "square.grid.3x3.square"
        case .bubble:     return "circle.dashed"
        case .slices:     return "line.3.horizontal.decrease.circle"
        case .vessel:     return "pill.fill"
        case .stack:      return "square.stack.3d.forward.dottedline"
        case .cascade:    return "rectangle.stack"
        case .prism:      return "cube"
        case .chrome:     return "sparkle.magnifyingglass"
        case .holo:       return "creditcard"
        case .lenticular: return "rectangle.split.3x1"
        case .moire:      return "circle.grid.cross"
        case .orrery:     return "globe.americas"
        case .bokeh:      return "camera.aperture"
        case .kaleido:    return "hexagon"
        case .dots:       return "circle.grid.3x3.fill"
        case .grain:      return "film"
        case .glitch:     return "waveform.path.badge.minus"
        case .crt:        return "tv"
        case .neon:       return "lightbulb.max"
        case .frost:      return "snowflake"
        case .duotone:    return "paintpalette"
        case .spin:       return "arrow.trianglehead.2.clockwise.rotate.90"
        case .journey:    return "iphone.gen3"
        case .agentStates: return "brain"
        case .waveform:   return "waveform"
        case .edgeGlow:   return "iphone.gen3.radiowaves.left.and.right"
        case .caption:    return "text.bubble"
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
        case .tunnel:
            return "Rings flying at you, the log of the radius scrolled by time so they accelerate toward the edge. Colour from the angle through the palette, twisted with depth. Warp speed, and cheap."
        case .constellation:
            return "Points drifting in the disc, joined by lines when they come close — the network look. Lines fade with distance so the graph breathes. Audio pulls the points apart and the lines snap."
        case .harmonograph:
            return "A pendulum drawing: a decaying Lissajous curve traced as a single line in the palette. Two frequencies and a phase make an endless family of figures; audio detunes them. The most ‘drawn by hand’ of the set."
        case .ink:
            return "Real feedback: a buffer that keeps the last frame, advected along a curl-noise flow and faded, with fresh ink from emitters orbiting the centre. Trails persist. This is the one thing a SwiftUI shader can’t do — it needs Metal compute and its own view."
        case .kaleido:
            return "Post: the angle folded into mirrored wedges. Anything under it becomes a mandala; the ring becomes a flower. Mostly a post effect over Aurora or Ink."
        case .dots:
            return "Post: an LED matrix. The image quantised to cells drawn as round dots that grow with brightness — what a matrix looks like through a diffuser. If the hardware ever gets a dot display, this is the preview."
        case .grain:
            return "Post: film grain, a vignette, optional desaturation. Everything looks shot rather than rendered. Subtle amounts are the ‘expensive’ look; the vignette alone is worth having."
        case .lightning:
            return "Arcs from the ring’s edge to its centre — jittered polylines redrawn every frame with a glow. Bolts strike on the beat (or on a synthetic rhythm). An alert state, a ‘thinking hard’ state, or a link to whatever sits in the middle."
        case .cells:
            return "Voronoi: the disc split into cells around drifting seeds, each in a palette colour, edges lit where they meet. Energy cells, honeycomb, scales — the knobs decide."
        case .warp:
            return "A starfield with depth: points fly outward from the centre, faster the closer they get, streaking on audio. Warp speed. The ‘working on it’ state that says something is happening fast."
        case .burst:
            return "A one-shot: tap the stage and particles explode from the pod and fall back — a celebration, a confirmation, an arrival. Event-driven, unlike everything else here. Tap it."
        case .symbols:
            return "Apple’s own SF Symbol effects on the glyph — bounce, pulse, variable colour, wiggle, breathe, rotate — and the replace transition between symbols. First-party motion the glyph state gets for free."
        case .shapeshift:
            return "A filled shape morphing circle → rounded square → star → blob, as a blend of signed distance fields, so the in-betweens are real shapes. The pod becoming a mark and back. Lit as a slab, edged in the palette."
        case .lattice:
            return "The dot-mesh sphere from the references: a lattice of dots on a sphere, each pushed along its normal by noise that flows over time and swells with audio, projected with depth so the near side is bigger and brighter. Colour by latitude and displacement. The most ‘ethereal, responsive’ thing here."
        case .stipple:
            return "The particle sphere from the reference: thousands of points on a sphere, weighted to the silhouette so it’s dense and bright at the rim and sparse in the middle — the way light catches dust on a ball. White by default; Tint puts it in the palette."
        case .tiles:
            return "Post: the reeded-glass reference — a panel of square glass tiles over the layer, each tile a small lens bending what’s behind it, with grout lines and a frosted haze. Coverage lets the panel sit over half the subject."
        case .bubble:
            return "A soap bubble: a thin film whose colour comes from interference — thickness varying with noise and draining downward sets which wavelength survives. Strongest at the rim (Fresnel), dark and see-through in the middle, a palette glow pooling at the bottom, two soft highlights. The bubble from day one, done as physics rather than geometry."
        case .slices:
            return "A gradient sphere cut into vertical slats, each a lens-shaped sliver with the colour running across and a fine moiré inside, with a squashed reflection below — the reference. Audio wobbles the gaps."
        case .vessel:
            return "A capsule with liquid in it: glass shell, liquid to a level that sloshes, bubbles rising, a bright meniscus. Level is a knob, or the audio — so it doubles as a meter (charging, listening, progress)."
        case .stack:
            return "Translucent planes receding into depth, each in the next palette colour, additive — the corridor from the reference. Sway rolls the whole stack; audio pushes it."
        case .cascade:
            return "Overlapping rounded shapes offset down an arc, each in the next palette colour — the Retoka poster. Multiply for ink on paper; additive for light."
        case .prism:
            return "A glass cube, edges drawn three times in red, green and blue offset along the edge normal — chromatic dispersion — with faint glass faces and a white core. The reference cube, as line art."
        case .chrome:
            return "Post: a material for anything with an edge. A bevel from the alpha gradient gives a normal; the normal reflects a striped environment (silver chrome), and with Iridescence, an interference palette (the holographic bolt). Over a glyph it’s the reference; over the ring it’s a chrome torus."
        case .holo:
            return "A holographic foil disc: two diffraction gratings whose rainbows sweep as a virtual view tilts (and as audio pushes it) — the sticker on a credit card, in the palette. Metal mixes toward a silver base. Later this is the device’s gyroscope."
        case .lenticular:
            return "A lenticular print: fine vertical lenses, each strip showing one of two pictures depending on the viewing angle. Two gradient spheres swap as the view sweeps, and the image tears halfway the way the real thing does. Two states in one surface."
        case .moire:
            return "Two fine gratings, one moving against the other: their interference makes patterns far larger than either. Ring or line mode. The moiré from inside the sliced sphere, on its own — hypnotic and nearly free."
        case .orrery:
            return "Rings in 3D on tilted axes, each turning at its own rate, drawn with the Prism dispersion edges — an armillary sphere, a gyroscope. A ‘thinking’ state with real depth, and a natural home for the ring itself."
        case .bokeh:
            return "Out-of-focus lights: discs in the palette at different depths — far ones big and soft, near ones small and sharp — with the bright edge ring a real lens gives. Focus slides which depth is sharp. Ethereal behind a glyph; the blobs-behind-glass reference, photographed."
        case .glitch:
            return "Post: digital damage in bursts — sliced rows, a channel split, inverted blocks — gated by the beat. An error state, or an interruption."
        case .crt:
            return "Post: a tube — barrel curvature, scanlines, phosphor bleed. Retro, and oddly right for an LED product."
        case .neon:
            return "Post: edges only, coloured by the source — anything becomes a neon sign of itself. Over the ring it’s a wireframe; over Sphere it’s a line drawing."
        case .frost:
            return "Post: frosted glass — pixels scattered along a noise field rather than blurred. What the pod looks like behind a diffuser that isn’t clean."
        case .duotone:
            return "Post: luminance mapped onto the palette. Makes anything wear the ring’s colours — a photo, Sparks, the whole screenshot."
        case .spin:
            return "Post: angular motion blur about the centre, with a radial component. The ring smears into itself; detail streaks round."
        case .journey:
            return "Tap the Nexus tab. The pod grows into a chat sheet; the ring becomes the input’s voice button; a second tap takes it full screen, voice only, the ring as the hero with the edge glowing. Tap the stage to advance, or let it cycle. Every stage is Liquid Glass on a spring."
        case .agentStates:
            return "The four things an agent is doing — idle, listening, thinking, speaking — as four motions on the same pod, with the transitions between them. Idle breathes; listening opens and follows you; thinking orbits; speaking pulses with the voice. Tap to advance."
        case .waveform:
            return "Voice as a waveform: bars, a line, or a ring of bars around the pod, driven by the spectrum (or a synthetic voice when the mic is off). The chat + voice interface needs one of these next to the ring."
        case .edgeGlow:
            return "The iOS 18 Siri signature: a glow that runs round the screen’s edge in the palette, breathing with the voice. The full-screen voice interface probably wants this with the ring in the middle, and it’s a blurred stroke — cheap."
        case .caption:
            return "The transcript: words arriving as the agent speaks — fading, blurring in, or typed — with a glow in the palette. The voice interface’s text, to go with Edge Glow and the hero ring."
        }
    }

    /// Whether the experiment is drawn *over* the existing ring (Bloom,
    /// Ripple, Sparks) rather than replacing it. The stage draws the ring
    /// underneath for those, so the comparison is "the ring, plus this".
    public var decoratesRing: Bool {
        switch self {
        case .bloom, .ripple, .sparks, .refraction, .chromatic, .rays, .kaleido, .dots, .grain, .glitch, .crt, .neon, .frost, .duotone, .spin, .tiles, .chrome: return true
        default: return false
        }
    }

    /// Can stand in for the ring inside the flows — see `LabState.hero`.
    /// The bases that draw a disc on their own.
    public var canBeHero: Bool {
        switch self {
        case .aurora, .orb, .mesh, .swarm, .liquid, .sphere, .tunnel, .constellation, .harmonograph, .ink, .volumetric, .sparks, .lightning, .cells, .warp, .shapeshift, .symbols, .lattice, .stipple, .bubble, .slices, .vessel, .stack, .cascade, .prism, .holo, .lenticular, .moire, .orrery, .bokeh: return true
        default: return false
        }
    }

    /// Whether the experiment draws the ring somewhere — so the Hero
    /// picker applies.
    public var drawsHero: Bool { usesPhoneCanvas || self == .morph }

    /// Drawn on a phone-shaped canvas rather than a disc: the flows,
    /// which are about the whole screen.
    public var usesPhoneCanvas: Bool {
        switch self {
        case .journey, .agentStates, .waveform, .edgeGlow, .caption: return true
        default: return false
        }
    }

    /// Advances through stages on tap — see `LabState.advance()`.
    public var isTappable: Bool { self == .journey || self == .agentStates || self == .burst || self == .symbols }

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
        case .tunnel: return [
            .init("rings", "Rings", 1...12, 4, "Rings per depth unit.", "%.0f"),
            .init("speed", "Speed", 0...4, 1, "How fast they fly."),
            .init("twist", "Twist", -2...2, 0.6, "Colour twists with depth."),
            .init("glow", "Ring Glow", 0...1, 0.4, "Sharp rings at 0, soft bands at 1."),
            .init("depth", "Depth Fade", 0...2, 0.5, "How fast the far end goes dark."),
        ]
        case .constellation: return [
            .init("count", "Points", 10...300, 80, "Points.", "%.0f"),
            .init("link", "Link Distance", 0.05...0.5, 0.2, "How close two points must be to join, as a fraction of the disc."),
            .init("drift", "Drift", 0...2, 0.6, "How fast they wander."),
            .init("size", "Point Size", 1...8, 3, "Points.", "%.0f pt"),
            .init("lineWidth", "Line Width", 0.5...4, 1, "Points.", "%.1f pt"),
        ]
        case .harmonograph: return [
            .init("fx", "Frequency X", 1...9, 3, "Pendulum X.", "%.1f"),
            .init("fy", "Frequency Y", 1...9, 2, "Pendulum Y.", "%.1f"),
            .init("phase", "Phase", 0...6.28, 1.57, "Offset between them."),
            .init("decay", "Decay", 0...1, 0.3, "How fast the figure shrinks along its length."),
            .init("length", "Length", 0.5...20, 8, "How much curve is drawn."),
            .init("lineWidth", "Line Width", 0.5...6, 1.5, "Points.", "%.1f pt"),
            .init("detune", "Detune", 0...0.5, 0.05, "Slow drift of the frequencies, so the figure evolves."),
        ]
        case .ink: return [
            .init("decay", "Persistence", 0.9...0.999, 0.985, "How much of the last frame survives each step."),
            .init("flowScale", "Flow Scale", 0.3...4, 1.2, "Size of the eddies."),
            .init("flowSpeed", "Flow Speed", 0...3, 0.8, "How fast the ink is carried."),
            .init("swirl", "Swirl", -2...2, 0.3, "Rotation about the centre."),
            .init("emitters", "Emitters", 1...8, 3, "Ink sources, one per palette colour.", "%.0f"),
            .init("radius", "Ink Radius", 0.02...0.3, 0.08, "Size of each source."),
            .init("orbit", "Orbit", 0...0.9, 0.45, "How far out the sources circle."),
        ]
        case .lightning: return [
            .init("bolts", "Bolts", 1...8, 3, "Arcs at once.", "%.0f"),
            .init("jitter", "Jitter", 0...1, 0.5, "How ragged the path is."),
            .init("rate", "Strike Rate", 0.5...8, 3, "Strikes per second when there’s no beat.", "%.1f"),
            .init("glow", "Glow", 0...1, 0.6, "Halo round each bolt."),
            .init("width", "Width", 0.5...5, 1.5, "Core line, points.", "%.1f pt"),
            .init("target", "Target", 0...1, 0, "0 strikes the centre, 1 arcs edge-to-edge."),
        ]
        case .cells: return [
            .init("scale", "Scale", 1...8, 3, "Cells across the disc."),
            .init("drift", "Drift", 0...1, 0.6, "How far seeds wander."),
            .init("edge", "Edge", 0...1, 0.4, "Lit edge width."),
            .init("fill", "Fill", 0...1, 0.5, "Cell body brightness."),
            .init("speed", "Speed", 0...2, 0.5, "Seed motion."),
        ]
        case .warp: return [
            .init("count", "Stars", 50...1500, 500, "Stars.", "%.0f"),
            .init("speed", "Speed", 0.1...4, 1, "How fast they come."),
            .init("streak", "Streak", 0...1, 0.5, "Length of the trails."),
            .init("size", "Size", 0.5...4, 1.5, "Point size at the edge, points."),
            .init("spread", "Spread", 0.2...1, 0.9, "Field size as a fraction of the disc."),
        ]
        case .burst: return [
            .init("count", "Particles", 20...600, 220, "Per burst.", "%.0f"),
            .init("speed", "Speed", 50...800, 320, "Initial velocity, points/s.", "%.0f"),
            .init("gravity", "Gravity", -600...1200, 500, "Fall back down. Negative floats up.", "%.0f"),
            .init("life", "Lifetime", 0.4...4, 1.6, "Seconds.", "%.1f s"),
            .init("size", "Size", 1...10, 4, "Points.", "%.0f pt"),
            .init("spread", "Spread", 0...1, 1, "1 is every direction, 0 is straight up."),
            .init("auto", "Auto Fire", 0...1, 1, "1 fires every few seconds by itself.", "%.0f"),
        ]
        case .symbols: return [
            .init("effect", "Effect", 0...5, 0, "0 bounce, 1 pulse, 2 variable colour, 3 wiggle, 4 breathe, 5 rotate.", "%.0f"),
            .init("size", "Size", 0.2...0.8, 0.45, "Glyph as a fraction of the disc."),
            .init("hold", "Hold", 0.5...6, 2, "Seconds before the glyph is replaced with the next.", "%.1f s"),
            .init("continuous", "Continuous", 0...1, 1, "1 keeps the effect running; 0 fires it on each replace.", "%.0f"),
        ]
        case .shapeshift: return [
            .init("hold", "Hold", 0.5...6, 2, "Seconds per shape.", "%.1f s"),
            .init("morph", "Morph", 0.1...1, 0.5, "Fraction of the hold spent morphing."),
            .init("edge", "Edge", 0...1, 0.4, "Lit edge width."),
            .init("shade", "Shade", 0...1, 0.6, "Slab lighting."),
            .init("spin", "Spin", -1...1, 0.15, "Rotation, radians per second."),
        ]
        case .lattice: return [
            .init("cols", "Columns", 16...120, 64, "Dots round the sphere.", "%.0f"),
            .init("rows", "Rows", 8...60, 32, "Dots pole to pole.", "%.0f"),
            .init("amp", "Displace", 0...0.6, 0.18, "How far the noise pushes the surface."),
            .init("scale", "Noise Scale", 0.5...5, 1.8, "Size of the bumps."),
            .init("flow", "Flow", 0...3, 1, "How fast the noise moves over the surface."),
            .init("dot", "Dot Size", 0.5...6, 2.2, "Points.", "%.1f pt"),
            .init("tilt", "Tilt", -1.2...1.2, 0.35, "Camera tilt, radians."),
            .init("spin", "Spin", -1...1, 0.25, "Rotation, radians per second."),
            .init("back", "Back Face", 0...1, 0.35, "How much of the far side shows through."),
        ]
        case .stipple: return [
            .init("count", "Points", 500...6000, 3500, "Points.", "%.0f"),
            .init("rim", "Rim Weight", 0...3, 1.6, "How much the silhouette is favoured."),
            .init("dot", "Dot Size", 0.5...4, 1.4, "Points.", "%.1f pt"),
            .init("spin", "Spin", -1...1, 0.15, "Rotation, radians per second."),
            .init("jitter", "Breathe", 0...0.3, 0.06, "Points drifting off the surface."),
            .init("tint", "Tint", 0...1, 0, "0 white, 1 palette.", "%.0f"),
        ]
        case .tiles: return [
            .init("cell", "Tile", 8...80, 28, "Tile size, points.", "%.0f pt"),
            .init("bulge", "Bulge", 0...1.5, 0.6, "How much each tile bends what’s behind it."),
            .init("frost", "Frost", 0...1, 0.35, "Haze and scatter."),
            .init("grout", "Grout", 0...1, 0.6, "The lines between tiles."),
            .init("coverage", "Coverage", 0...1, 1, "How much of the width the panel covers, from the right."),
            .init("orientation", "Flutes", 0...2, 0, "0 square tiles, 1 vertical flutes (reeded glass), 2 horizontal.", "%.0f"),
        ]
        case .bubble: return [
            .init("thickness", "Film", 0...2, 0.8, "Film thickness — how many colour cycles across."),
            .init("drain", "Drain", 0...2, 0.6, "Film draining downward over time."),
            .init("iridescence", "Iridescence", 0...2, 1, "The film's colour strength."),
            .init("rim", "Rim", 0...2, 1, "The bright edge."),
            .init("pool", "Pool", 0...2, 0.8, "Glow gathering at the bottom."),
            .init("highlight", "Highlights", 0...2, 1, "The two specular hits."),
            .init("wobble", "Wobble", 0...1, 0.5, "The bubble is never quite round."),
        ]
        case .slices: return [
            .init("slats", "Slats", 6...60, 22, "Slices across.", "%.0f"),
            .init("duty", "Width", 0.2...0.95, 0.55, "Slat width as a fraction of the pitch."),
            .init("wobble", "Wobble", 0...1, 0.3, "Slat widths breathing."),
            .init("moire", "Moiré", 0...1, 0.5, "The fine ring pattern inside each slat."),
            .init("tilt", "Tilt", -0.6...0.6, 0, "Slat angle, radians."),
            .init("reflect", "Reflection", 0...1, 0.8, "The squashed reflection below."),
        ]
        case .vessel: return [
            .init("level", "Level", 0...1, 0.45, "How full. Audio adds to it."),
            .init("slosh", "Slosh", 0...1, 0.5, "Surface movement."),
            .init("bubbles", "Bubbles", 0...1, 0.8, "Rising bubbles."),
            .init("rim", "Glass", 0...2, 1, "Shell visibility."),
            .init("glow", "Glow", 0...1, 0.7, "Liquid luminance."),
            .init("tilt", "Tilt", -1.6...1.6, 0, "Rotation, radians. ±1.57 is horizontal."),
        ]
        case .stack: return [
            .init("count", "Planes", 2...16, 9, "Planes.", "%.0f"),
            .init("depth", "Depth", 0...1, 0.6, "How far back the last plane sits."),
            .init("opacity", "Opacity", 0.05...0.6, 0.18, "Per plane."),
            .init("shape", "Shape", 0...1, 0, "0 squares, 1 discs.", "%.0f"),
            .init("sway", "Sway", 0...1, 0.3, "The stack rolling."),
            .init("perspective", "Skew", -1...1, 0.5, "Sideways shift with depth."),
        ]
        case .cascade: return [
            .init("count", "Shapes", 2...12, 6, "Shapes.", "%.0f"),
            .init("step", "Step", 0...1.2, 0.35, "Offset between shapes, in shape heights."),
            .init("opacity", "Opacity", 0.05...1, 0.22, "Per shape. Additive stacks up fast — keep it low unless multiplying."),
            .init("swing", "Swing", 0...1, 0.3, "The arc they fall along."),
            .init("corner", "Corner", 0...0.5, 0.35, "Corner radius as a fraction of size."),
            .init("multiply", "Multiply", 0...1, 0, "1 multiplies (ink); 0 adds (light).", "%.0f"),
        ]
        case .prism: return [
            .init("dispersion", "Dispersion", 0...3, 1, "How far the colours split at the edges."),
            .init("spin", "Spin", -1...1, 0.3, "Rotation, radians per second."),
            .init("tilt", "Tilt", -1...1, 0.5, "Camera tilt."),
            .init("faces", "Faces", 0...0.4, 0.08, "Glass face opacity."),
            .init("edge", "Edge", 0.5...4, 1.2, "Core line width, points."),
            .init("glow", "Glow", 0...1, 0.5, "Halo round the edges."),
        ]
        case .chrome: return [
            .init("bevel", "Bevel", 1...24, 6, "Bevel width, points.", "%.0f pt"),
            .init("iridescence", "Iridescence", 0...1, 0.6, "0 silver chrome, 1 holographic."),
            .init("shine", "Shine", 0...2, 1, "Environment brightness."),
            .init("keep", "Keep Source", 0...1, 0.15, "How much of the original colour shows."),
        ]
        case .holo: return [
            .init("pitch", "Grating", 1...30, 5, "Bands per disc. Low is broad rainbow sweeps; high is fine foil."),
            .init("tilt", "Tilt", 0...1, 0.5, "How far the virtual view wanders."),
            .init("angle", "Angle", 0...3.14, 0.6, "Grating orientation, radians."),
            .init("metal", "Metal", 0...1, 0.15, "Toward a silver base."),
            .init("noise", "Warp", 0...1, 0.4, "Bends the gratings."),
        ]
        case .lenticular: return [
            .init("lenses", "Lenses", 6...80, 30, "Strips across.", "%.0f"),
            .init("sweep", "Sweep", 0...3, 0.6, "How fast the view swings between the two pictures."),
            .init("shade", "Shade", 0...1, 0.7, "Sphere shading on both pictures."),
            .init("tear", "Tear", 0...1, 0.5, "Raggedness at the changeover."),
        ]
        case .moire: return [
            .init("pitch", "Pitch", 20...200, 90, "Grating fineness."),
            .init("offset", "Offset", 0...1, 0.25, "Separation of the two gratings."),
            .init("speed", "Speed", 0...2, 0.4, "Drift."),
            .init("contrast", "Contrast", 0...1, 0.5, "Sharpens the beats."),
            .init("mode", "Mode", 0...1, 0, "0 rings, 1 lines.", "%.0f"),
        ]
        case .orrery: return [
            .init("rings", "Rings", 1...8, 4, "Rings.", "%.0f"),
            .init("spin", "Spin", 0...2, 0.5, "Base rotation rate."),
            .init("dispersion", "Dispersion", 0...3, 1, "Colour split at the edges."),
            .init("width", "Width", 0.5...4, 1.2, "Core line, points."),
            .init("spacing", "Spacing", 0...0.8, 0.35, "How much smaller each inner ring is."),
            .init("glow", "Glow", 0...1, 0.5, "Halo in the ring's palette colour."),
        ]
        case .bokeh: return [
            .init("count", "Lights", 10...120, 50, "Lights.", "%.0f"),
            .init("size", "Size", 0.3...3, 1, "Multiplier."),
            .init("edge", "Edge Ring", 0...1.5, 0.8, "The bright rim real bokeh has."),
            .init("drift", "Drift", 0...2, 0.5, "How fast they wander."),
            .init("sides", "Aperture", 0...9, 0, "0 round; 5–9 blades.", "%.0f"),
            .init("focus", "Focus", 0...1, 0.8, "Which depth is sharp. Sweep it."),
        ]
        case .glitch: return [
            .init("amount", "Amount", 0...1, 0.5, "Slice offset and split."),
            .init("blocks", "Blocks", 0...1, 0.4, "Inverted blocks."),
            .init("idle", "Idle Rate", 0...1, 0.2, "How often it glitches with no beat."),
        ]
        case .crt: return [
            .init("curve", "Curvature", 0...1, 0.4, "Barrel distortion."),
            .init("lines", "Scanlines", 0...1, 0.5, "Line darkness."),
            .init("bleed", "Bleed", 0...4, 1.2, "Phosphor colour bleed, points."),
        ]
        case .neon: return [
            .init("thickness", "Thickness", 0.5...6, 1.5, "Edge sample distance, points."),
            .init("gain", "Gain", 0.5...8, 3, "Edge brightness."),
            .init("keep", "Keep Source", 0...1, 0.1, "How much of the original shows through."),
        ]
        case .frost: return [
            .init("amount", "Amount", 0...30, 8, "Scatter distance, points.", "%.0f pt"),
            .init("scale", "Crystal Size", 4...80, 20, "Noise scale, points.", "%.0f pt"),
            .init("melt", "Melt", 0...2, 0.3, "How fast the pattern moves."),
        ]
        case .duotone: return [
            .init("mix", "Mix", 0...1, 1, "0 leaves the source."),
            .init("shift", "Shift", 0...1, 0, "Where on the palette black lands."),
        ]
        case .spin: return [
            .init("angle", "Angle", 0...1.5, 0.25, "Arc length of the blur, radians."),
            .init("radial", "Radial", 0...0.5, 0, "Zoom component."),
        ]
        case .kaleido: return [
            .init("segments", "Segments", 2...24, 6, "Mirrored wedges.", "%.0f"),
            .init("rotate", "Rotate", -2...2, 0.2, "Turns per second-ish."),
            .init("mix", "Mix", 0...1, 1, "0 leaves the source; 1 is fully folded."),
        ]
        case .dots: return [
            .init("cell", "Cell", 3...40, 10, "Matrix pitch, points.", "%.0f pt"),
            .init("roundness", "Brightness Size", 0...1, 0.7, "Dots grow with brightness."),
            .init("gain", "Gain", 0.5...3, 1.4, "Dot brightness."),
            .init("lens", "Lens", 0...1.5, 0, "Each dot bends what’s behind it, like a glass bead."),
        ]
        case .grain: return [
            .init("amount", "Grain", 0...0.5, 0.08, "Noise amplitude."),
            .init("vignette", "Vignette", 0...1, 0.5, "Corner darkening."),
            .init("desat", "Desaturate", 0...1, 0, "Toward monochrome."),
        ]
        case .journey: return [
            .init("hold", "Hold", 1...8, 3, "Seconds per stage when cycling.", "%.1f s"),
            .init("auto", "Auto Cycle", 0...1, 1, "1 cycles on the clock; 0 only advances on tap.", "%.0f"),
            .init("spring", "Spring", 0.2...1.2, 0.5, "Response — lower is snappier."),
            .init("bounce", "Bounce", 0...1, 0.15, "Damping headroom."),
            .init("sheet", "Sheet Height", 0.4...0.95, 0.72, "The chat sheet, as a fraction of the screen."),
            .init("role", "Ring Role", 0...2, 2, "In chat: 0 hero above messages, 1 avatar on replies, 2 the input’s voice button.", "%.0f"),
            .init("hero", "Hero Size", 0.3...0.9, 0.55, "The ring in the voice stage, as a fraction of screen width."),
            .init("glow", "Edge Glow", 0...1, 0.7, "Edge glow in the voice stage."),
            .init("dim", "Dim", 0...1, 0.6, "How much the app dims behind the sheet."),
        ]
        case .agentStates: return [
            .init("hold", "Hold", 0.5...8, 2.5, "Seconds per state when cycling.", "%.1f s"),
            .init("auto", "Auto Cycle", 0...1, 1, "1 cycles; 0 only advances on tap.", "%.0f"),
            .init("breath", "Idle Breath", 0...0.2, 0.05, "Idle scale swing."),
            .init("open", "Listen Open", 0...0.6, 0.25, "How much the ring opens when listening."),
            .init("orbit", "Think Orbit", 0.5...4, 1.6, "Thinking comet speed."),
            .init("pulse", "Speak Pulse", 0...0.5, 0.2, "Speaking scale swing per syllable."),
            .init("spring", "Spring", 0.2...1.2, 0.45, "Transition response."),
        ]
        case .waveform: return [
            .init("style", "Style", 0...2, 0, "0 bars, 1 line, 2 ring of bars round the pod.", "%.0f"),
            .init("bars", "Bars", 8...96, 32, "Segments.", "%.0f"),
            .init("height", "Height", 0.1...1, 0.5, "Peak height as a fraction of the area."),
            .init("thickness", "Thickness", 1...12, 4, "Bar or line width, points.", "%.0f pt"),
            .init("smooth", "Smoothing", 0...1, 0.5, "How much neighbours share energy."),
            .init("mirror", "Mirror", 0...1, 1, "Symmetric about the middle.", "%.0f"),
            .init("synth", "Synthetic Voice", 0...1, 0.6, "Fake speech energy when the mic is off."),
        ]
        case .edgeGlow: return [
            .init("width", "Width", 2...80, 24, "Glow band, points.", "%.0f pt"),
            .init("blur", "Blur", 0...60, 22, "Softness, points.", "%.0f pt"),
            .init("breathe", "Breathe", 0...1, 0.4, "Idle pulsing."),
            .init("rotate", "Rotate", -1...1, 0.3, "The palette runs round the edge."),
            .init("inset", "Inset", 0...40, 0, "Distance in from the edge.", "%.0f pt"),
            .init("ringSize", "Hero Ring", 0...0.9, 0.5, "A ring in the middle, as a fraction of width. 0 hides it."),
        ]
        case .caption: return [
            .init("style", "Style", 0...2, 1, "0 fade, 1 blur in, 2 typewriter.", "%.0f"),
            .init("rate", "Words / s", 1...12, 4, "Arrival rate.", "%.0f"),
            .init("size", "Size", 14...44, 24, "Type size.", "%.0f pt"),
            .init("glow", "Glow", 0...1, 0.4, "Glow behind the newest words."),
            .init("hold", "Hold", 1...10, 4, "Seconds a sentence stays before the next.", "%.1f s"),
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
    case bloom, rays, ripple, refraction, chromatic, kaleido, dots, grain, glitch, crt, neon, frost, duotone, spin, tiles, chrome
    public var id: String { rawValue }
    /// The experiment whose knobs this effect uses.
    public var experiment: LabExperiment {
        switch self {
        case .bloom: return .bloom
        case .rays: return .rays
        case .ripple: return .ripple
        case .refraction: return .refraction
        case .chromatic: return .chromatic
        case .kaleido: return .kaleido
        case .dots: return .dots
        case .grain: return .grain
        case .glitch: return .glitch
        case .crt: return .crt
        case .neon: return .neon
        case .frost: return .frost
        case .duotone: return .duotone
        case .spin: return .spin
        case .tiles: return .tiles
        case .chrome: return .chrome
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
    /// What the flows draw where the ring goes — the ring itself, or any
    /// of the animation labs (with the post stack). Chris, 2026-09-14:
    /// "the option to use these new animation labs within the agent
    /// screens (instead of just the ring)".
    @Published public var hero: LabExperiment? = nil
    /// Manual stage for the tappable flows: how many taps so far. The
    /// flow adds this to its clock-driven stage, so a tap always moves
    /// it on from wherever it is.
    @Published public var taps: Int = 0
    @Published public var lastTap: Date = .distantPast

    public init() {}

    /// "What happens when I tap on the Nexus tab?" — answered by tapping.
    public func advance() {
        taps += 1
        lastTap = Date()
    }

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
    /// Taps so far on a tappable flow, and when the last one was.
    public var taps: Int = 0
    public var sinceTap: Double = .infinity
    /// What stands in for the ring inside a flow — `nil` is the ring.
    public var hero: LabExperiment? = nil
    /// Post effects over the hero.
    public var heroPost: [LabPostEffect] = []

    public init(time: Double, intensity: Double, audio: Double, colors: [Color], diameter: CGFloat, darkStage: Bool,
                params: [String: Double] = [:], bands: LabAudioBands = LabAudioBands(), glyph: String? = nil,
                taps: Int = 0, sinceTap: Double = .infinity,
                hero: LabExperiment? = nil, heroPost: [LabPostEffect] = []) {
        self.time = time
        self.intensity = intensity
        self.audio = audio
        self.colors = colors
        self.diameter = diameter
        self.darkStage = darkStage
        self.params = params
        self.bands = bands
        self.glyph = glyph
        self.taps = taps
        self.sinceTap = sinceTap
        self.hero = hero
        self.heroPost = heroPost
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
