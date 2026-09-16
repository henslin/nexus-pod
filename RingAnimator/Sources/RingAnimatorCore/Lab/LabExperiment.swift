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
    case cells
    case warp
    case symbols
    case shapeshift
    case lattice
    case stipple
    case bubble
    case slices
    case stack
    case cascade
    case prism
    case holo
    case lenticular
    case moire
    case orrery
    case bokeh
    case frostOrb
    case globe
    case silk
    case liquidRing
    case tide
    case droplet
    case pour
    case pool
    case caustics
    case lava
    case jelly
    case slick
    case deep
    case nebula
    case thinkingOrbs
    case orbKit
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
    case water
    case haze
    case fizz
    case glints
    case parallax
    case focus
    // UI — surfaces the orb sits in.
    case buttonGlow
    case sheet
    // Flows — what a touch does.
    case hold
    // Libraries.dev kits (Vendor/).
    case beamKit
    case gooey
    case metal
    // Flows — the tap-on-Nexus question, on a phone canvas.
    case journey
    case agentStates
    case waveform
    case edgeGlow
    case caption
    case system
    case sunflower

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
        case .cells:      return "Cells"
        case .warp:       return "Warp"
        case .symbols:    return "Symbols"
        case .shapeshift: return "Shapeshift"
        case .lattice:    return "Lattice"
        case .stipple:    return "Stipple"
        case .tiles:      return "Tiles"
        case .bubble:     return "Bubble"
        case .slices:     return "Slices"
        case .stack:      return "Stack"
        case .cascade:    return "Cascade"
        case .prism:      return "Prism"
        case .chrome:     return "Chrome"
        case .holo:       return "Holo"
        case .lenticular: return "Lenticular"
        case .moire:      return "Moiré"
        case .orrery:     return "Orrery"
        case .bokeh:      return "Bokeh"
        case .frostOrb:   return "Frost Orb"
        case .globe:      return "Globe"
        case .silk:       return "Silk"
        case .liquidRing: return "Liquid Ring"
        case .tide:       return "Tide"
        case .droplet:    return "Droplet"
        case .pour:       return "Pour"
        case .pool:       return "Pool"
        case .caustics:   return "Caustics"
        case .lava:       return "Lava"
        case .jelly:      return "Jelly"
        case .slick:      return "Slick"
        case .deep:       return "Deep"
        case .nebula:     return "Nebula"
        case .thinkingOrbs: return "Thinking Orbs · Native"
        case .orbKit:     return "Thinking Orbs"
        case .beamKit:    return "Border Beam"
        case .gooey:      return "Gooey"
        case .metal:      return "Metal"
        case .water:      return "Water"
        case .haze:       return "Haze"
        case .fizz:       return "Fizz"
        case .glints:     return "Glints"
        case .parallax:   return "Parallax"
        case .focus:      return "Focus"
        case .buttonGlow: return "Button Glow"
        case .sheet:      return "Sheet"
        case .hold:       return "Hold"
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
        case .system:     return "Nexus System"
        case .sunflower:  return "Bloom Field"
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
        case .cells:      return "Metal · colorEffect"
        case .warp:       return "SwiftUI · Canvas"
        case .symbols:    return "SwiftUI · SF Symbol effects"
        case .shapeshift: return "Metal · colorEffect (SDF)"
        case .lattice:    return "SwiftUI · Canvas"
        case .stipple:    return "SwiftUI · Canvas"
        case .tiles:      return "Metal · layerEffect"
        case .bubble:     return "Metal · colorEffect"
        case .slices:     return "Metal · colorEffect"
        case .stack:      return "SwiftUI · Canvas"
        case .cascade:    return "SwiftUI · Canvas"
        case .prism:      return "SwiftUI · Canvas"
        case .chrome:     return "Metal · layerEffect"
        case .holo:       return "Metal · colorEffect"
        case .lenticular: return "Metal · colorEffect"
        case .moire:      return "Metal · colorEffect"
        case .orrery:     return "SwiftUI · Canvas"
        case .bokeh:      return "SwiftUI · Canvas"
        case .frostOrb:   return "Metal · colorEffect"
        case .globe:      return "Metal · colorEffect"
        case .silk:       return "Metal · colorEffect"
        case .liquidRing: return "Metal · colorEffect"
        case .tide:       return "Metal · colorEffect (ray-marched)"
        case .droplet, .pour, .pool, .caustics, .lava, .jelly, .slick, .deep: return "Metal · colorEffect"
        case .nebula:     return "Metal · colorEffect (ray-marched)"
        case .thinkingOrbs: return "SwiftUI · Canvas"
        case .orbKit:     return "Libraries.dev · ThinkingOrbsKit"
        case .beamKit:    return "Libraries.dev · BorderBeamKit"
        case .gooey:      return "SwiftUI · Canvas filters"
        case .metal:      return "Metal · colorEffect + distortionEffect"
        case .water, .haze, .fizz, .glints, .parallax, .focus: return "Metal · layerEffect"
        case .buttonGlow: return "SwiftUI · Liquid Glass + glow"
        case .sheet:      return "SwiftUI · Liquid Glass"
        case .hold:       return "SwiftUI · long press + springs"
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
        case .system:     return "Spec · every slot, played"
        case .sunflower:  return "SwiftUI · Canvas + Speech"
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
        case .cells:      return "hexagon.fill"
        case .warp:       return "sparkle"
        case .symbols:    return "star.circle"
        case .shapeshift: return "square.on.circle"
        case .lattice:    return "globe"
        case .stipple:    return "circle.dotted"
        case .tiles:      return "square.grid.3x3.square"
        case .bubble:     return "circle.dashed"
        case .slices:     return "line.3.horizontal.decrease.circle"
        case .stack:      return "square.stack.3d.forward.dottedline"
        case .cascade:    return "rectangle.stack"
        case .prism:      return "cube"
        case .chrome:     return "sparkle.magnifyingglass"
        case .holo:       return "creditcard"
        case .lenticular: return "rectangle.split.3x1"
        case .moire:      return "circle.grid.cross"
        case .orrery:     return "globe.americas"
        case .bokeh:      return "camera.aperture"
        case .frostOrb:   return "cloud.circle"
        case .globe:      return "drop.circle.fill"
        case .silk:       return "leaf"
        case .liquidRing: return "circle.dotted.and.circle"
        case .tide:       return "water.waves.and.arrow.trianglehead.down"
        case .droplet:    return "drop"
        case .pour:       return "arrow.down.to.line.compact"
        case .pool:       return "circle.circle"
        case .caustics:   return "light.beacon.max"
        case .lava:       return "flame"
        case .jelly:      return "circle.bottomhalf.filled"
        case .slick:      return "rainbow"
        case .deep:       return "sun.horizon"
        case .nebula:     return "cloud.fill"
        case .thinkingOrbs: return "circle.hexagongrid.circle"
        case .orbKit:     return "shippingbox"
        case .beamKit:    return "shippingbox"
        case .gooey:      return "plus.circle.fill"
        case .metal:      return "circle.circle"
        case .water:      return "water.waves"
        case .haze:       return "cloud.fog"
        case .fizz:       return "bubbles.and.sparkles"
        case .glints:     return "sparkle"
        case .parallax:   return "square.3.layers.3d"
        case .focus:      return "camera.aperture"
        case .buttonGlow: return "capsule"
        case .sheet:      return "rectangle.bottomhalf.inset.filled"
        case .hold:       return "hand.tap"
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
        case .system:     return "square.grid.2x2"
        case .sunflower:  return "sun.max.fill"
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
            return "Liquid Glass itself: one glass shape morphing through the states below — pod, pill, card, sheet, full screen — with the content riding inside. Add states, remove them, and give any state (or all of them) an edge glow, a waveform, a caption. This is the pod-to-sheet expansion as a container Apple already ships, and the workbench for what each state carries."
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
        case .cells:
            return "Voronoi: the disc split into cells around drifting seeds, each in a palette colour, edges lit where they meet. Energy cells, honeycomb, scales — the knobs decide."
        case .warp:
            return "A starfield with depth: points fly outward from the centre, faster the closer they get, streaking on audio. Warp speed. The ‘working on it’ state that says something is happening fast."
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
        case .frostOrb:
            return "The light-mode family from the references: a frosted glass sphere on a pale ground with the colour inside it — soft palette blobs drifting behind a milky shell — a white Fresnel rim, a highlight, a soft shadow beneath. Put a glyph on it. Turn Dark Stage off; this one was born for daylight."
        case .globe:
            return "A clear glass sphere with liquid sloshing inside, the surface a wave, a bright meniscus and a caustic under it. Light-mode. Level is a knob or the audio, like Vessel — but round, so it can be the pod."
        case .silk:
            return "A translucent pastel membrane that folds: nearly white where it faces you, colour only where it’s seen edge-on — the folds and the rim — with a silhouette that wanders. The softest thing here. Light-mode."
        case .liquidRing:
            return "The ring as a fluid: a band whose edges are pushed by flowing noise, white-hot where the flow bunches, with a faint dot field rippling inside — the temperature-dial reference. This is the ring’s own identity, reimagined."
        case .tide:
            return "Water in a sphere, tumbling in 3D — the three references at once. A ray per pixel through the sphere; the liquid is everything below a plane whose ‘down’ slowly turns, so you see the surface from above as a wavy disc, then edge-on as a line (the fish tank), then from underneath. Thickness sets the colour. Density 0 is the clear film; Frost is the blue one behind glass. Audio sloshes it."
        case .droplet:
            return "A water drop: a disc sagging under its own weight, wobbling in modes that swell on audio, refracting the palette behind it like a lens, with a Fresnel rim and a window highlight. Light-mode."
        case .pour:
            return "The sphere filling from a stream at the top — ripples where it lands, foam at the surface — then holding, then draining. The pod filling as it listens. Level follows the cycle, plus the audio."
        case .pool:
            return "Water from above: rings spreading from drops, refracting a palette floor, caustic brightening on the slopes, a slow swell. Audio makes the drops bigger."
        case .caustics:
            return "The bright web light makes on the bottom of a pool: folded noise, layers drifting against each other, tinted by the palette. Under water, on its own."
        case .lava:
            return "A lava lamp: warm blobs rising from the bottom, stretching as they move, merging and sinking — one metaball field with a vertical drift and a glow."
        case .jelly:
            return "A gelatin sphere: its outline rings in a few spring modes on a beat and settles, translucent with a lit core and a shell highlight. Higher modes ring faster, like the real thing."
        case .slick:
            return "Oil on water: thin-film colour from a swirling thickness field over a dark reflective surface. The water-surface rainbow, moving."
        case .deep:
            return "Looking up from under water: light shafts fanning down from the surface, a caustic web up top, motes drifting up, the palette darkening with depth."
        case .nebula:
            return "A cloud inside glass: volumetric noise ray-marched through the sphere, lit from a direction, drifting — the frosted-blue reference’s interior done as a real volume. Nebula in a Frost Orb is the ‘thinking’ state."
        case .thinkingOrbs:
            return "A cloud of dots with nine states of motion — Working, Searching, Solving, Listening, Connecting, Weaving, Composing, Breathing, Shaping — the agent’s verbs as motion, each a different way for the same dots to move. Every position is a function of time, so the state switches are clean."
        case .orbKit:
            return "Libraries.dev’s Thinking orbs, the real SwiftUI port (MIT, vendored): nine states, two tuned size presets drawn at any display size, a theme, a speed. Beside our own Thinking Orbs so the two can be compared on one stage."
        case .beamKit:
            return "Libraries.dev’s Border beam, the real SwiftUI port (MIT, vendored): rotate (large / small / line) and pulse (outside / inner) families, four colour variants, and their tuning — stroke, inner glow, bloom, brightness, saturation, hue range. Also available as a Morph adornment beside our edge glow."
        case .gooey:
            return "The Nexus tab as a gooey +: it sits in the pod’s slot and opens into items to the left along the bar (Move, Melt) or up and to the left (Morph, Bend) with a gooey stretch — SwiftUI’s own Canvas blur + alpha-threshold is the goo — so nothing leaves the screen. Their physics: durations, staggers, spread, anticipation, icon timing. Tap to open and close."
        case .metal:
            return "A polished metal ring round a control — circle button, button, text or badge — chromatic, silver or gold, with an inner shadow, a glow that appears on hover, a cursor-driven dent, and a reflection that follows the pointer (touch on the phone). The libraries.dev Metal v2, natively, with its rail."
        case .water:
            return "Post: the layer seen through a rippling water surface — a noise height field refracts it, caustics brighten the slopes. A glyph under Water is a glyph under water."
        case .haze:
            return "Post: a soft palette veil breathing over the layer — depth fog. Makes anything recede."
        case .fizz:
            return "Post: small bubbles rising over the layer, bright rims and dark centres, each on its own lane. Carbonation for anything."
        case .glints:
            return "Post: a star filter — bright points throw four thin streaks. The sparkle on a wet surface, or on Stipple’s rim."
        case .parallax:
            return "Post: depth for a flat thing — a dark, softened copy offset one way (its shadow on the glass behind) and a light copy the other (the light on its edge). Under Liquid Glass this is what makes a layer read as an object with thickness."
        case .focus:
            return "Post: depth of field. Sharp at a focal point you place, blurring with distance from it — and the blur is a disc of jittered taps, so highlights bloom into bokeh rather than smearing. Band mode focuses a horizontal slice instead, like a tilt-shift."
        case .buttonGlow:
            return "UI: the orb’s glow escaping onto a control — a Liquid Glass capsule button with the palette running round its edge, breathing with the voice, the orb beside it. For the send button, the mic button, a pill that’s ‘live’."
        case .sheet:
            return "UI: the agent sheet on its own — Liquid Glass, the hero at the top, a transcript arriving, a waveform in the input bar — without the flow around it, so the sheet itself can be designed. The hero is whatever Hero says."
        case .hold:
            return "Flow: press and hold the stage. The pod grows with the hold into a full-screen listening UI — edge glow, hero, ‘Listening…’ — and letting go turns it into talking, then it settles back. The long-press question, answered by holding."
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
        case .sunflower:
            return "The Bloom app, brought in: a sunflower’s seed spiral filling the screen, and blooms of colour opening across it — on the clock, on a tap, and on your voice. A full-screen, ethereal way to talk to the agent: the field is the agent. A live transcript, natively animated, sits at the bottom when Audio Reactive is on."
        case .system:
            return "The product, assembled. Every slot the Nexus surface needs — the pod, a look per agent state, the menu a tap reveals, the surface each action opens, what tap and long press do — filled from the Lab and played end to end. Tap to step; hold to talk."
        }
    }

    /// Whether the experiment is drawn *over* the existing ring (Bloom,
    /// Ripple, Sparks) rather than replacing it. The stage draws the ring
    /// underneath for those, so the comparison is "the ring, plus this".
    public var decoratesRing: Bool {
        switch self {
        case .bloom, .ripple, .sparks, .refraction, .chromatic, .rays, .kaleido, .dots, .grain, .glitch, .crt, .neon, .frost, .duotone, .spin, .tiles, .chrome, .water, .haze, .fizz, .glints, .parallax, .focus: return true
        default: return false
        }
    }

    /// How much of the disc the experiment's content spans at its
    /// defaults — the sphere-based ones sit inside a margin, the ring
    /// ones inside the pod's proportion. `LabState.fill` scales by the
    /// inverse so any of them can take up the whole circle (Chris,
    /// 2026-09-15: "whatever option we go with, we'll want it to fill").
    public var naturalFill: Double {
        switch self {
        case .tide: return 0.9
        case .frostOrb: return 0.78
        case .globe: return 0.9
        case .silk: return 0.85
        case .liquidRing: return 0.92
        case .bubble: return 0.97
        case .orb: return 0.96
        case .refraction: return 0.75
        case .lattice, .stipple: return 0.78
        case .harmonograph: return 0.88
        case .constellation: return 0.92
        case .warp: return 0.9
        case .stack, .cascade: return 0.7
        case .prism: return 0.75
        case .orrery: return 0.78
        case .volumetric: return 0.95
        case .droplet: return 0.92
        case .pour, .nebula: return 0.92
        case .jelly: return 0.93
        case .bloom, .ripple, .sparks, .rays, .chromatic, .kaleido, .dots, .grain, .glitch, .crt, .neon, .frost, .duotone, .spin, .tiles, .chrome, .water, .haze, .fizz, .glints, .parallax, .focus:
            return 0.72   // the ring underneath
        default: return 0.97
        }
    }

    /// Can stand in for the ring inside the flows — see `LabState.hero`.
    /// The bases that draw a disc on their own.
    public var canBeHero: Bool {
        switch self {
        case .aurora, .orb, .mesh, .swarm, .liquid, .sphere, .tunnel, .constellation, .harmonograph, .ink, .volumetric, .sparks, .cells, .warp, .shapeshift, .symbols, .lattice, .stipple, .bubble, .slices, .stack, .cascade, .prism, .holo, .lenticular, .moire, .orrery, .bokeh, .frostOrb, .globe, .silk, .liquidRing, .tide, .droplet, .pour, .pool, .caustics, .lava, .jelly, .slick, .deep, .nebula, .thinkingOrbs, .orbKit: return true
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
        case .journey, .agentStates, .waveform, .edgeGlow, .caption, .buttonGlow, .sheet, .hold, .system, .sunflower: return true
        default: return false
        }
    }

    /// Advances through stages on tap — see `LabState.advance()`.
    public var isTappable: Bool { self == .journey || self == .agentStates || self == .symbols || self == .gooey || self == .system || self == .sunflower }

    /// Reads the pointer — hover on the Mac, touch on the phone.
    public var usesPointer: Bool { self == .metal || self == .sunflower }

    /// Responds to press-and-hold — see `LabState.hold`.
    public var isHoldable: Bool { self == .hold || self == .system }

    /// Libraries.dev's nine orb verbs, for the flows' per-state chips.
    public static let orbVerbs = ["Working", "Searching", "Solving", "Listening", "Connecting", "Weaving", "Composing", "Breathing", "Shaping"]

    /// Hidden from the lists but kept in code — the UI room narrowed to
    /// Morph (Chris, 2026-09-15: "comment these out"). Their pieces live
    /// on as Morph adornments (edge glow, waveform, caption).
    public var isHidden: Bool {
        switch self {
        case .buttonGlow, .sheet, .waveform, .edgeGlow, .caption: return true
        // Chris, 2026-09-15: "Let's go with theirs." Libraries.dev's
        // Thinking Orbs is the one; the native sketch stays in code.
        case .thinkingOrbs: return true
        default: return false
        }
    }

    /// Which room of the Lab this lives in.
    public var section: LabSection {
        switch self {
        case .journey, .agentStates, .hold, .sunflower: return .flows
        case .system: return .system
        case .waveform, .edgeGlow, .caption, .morph, .buttonGlow, .sheet, .beamKit, .gooey, .metal: return .ui
        default: return .orb
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
            .init("bands", "Bands", 0...1, 0, "Sharpens the swirl into glossy stripes — the marble."),
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
            .init("hold", "Hold", 0.5...6, 2, "Seconds in each state.", "%.1f s", group: "Morphing"),
            .init("spring", "Spring", 0.2...1.2, 0.55, "Response — lower is snappier.", group: "Morphing"),
            .init("bounce", "Bounce", 0...1, 0.2, "Damping headroom.", group: "Morphing"),
            .init("pingpong", "Order", 0...1, 1, "Round: first to last and back to the first. Ping-pong: up the list and back down.", "%.0f", group: "Morphing", choices: ["Round", "Ping-pong"]),
            .init("transIn", "Enter Time", 0.1...2, 0.5, "How long a state's content and adornments take to arrive.", "%.1f s", group: "Morphing"),
            .init("transOut", "Leave Time", 0.1...2, 0.35, "How long they take to leave before the next state.", "%.1f s", group: "Morphing"),
            .init("glowStyle", "Style", 0...2, 2, "What the edge carries.", "%.0f", group: "Edge Glow", choices: ["Glow", "Tracer", "Both"]),
            .init("glowWidth", "Glow Width", 2...40, 14, "The glow band, points.", "%.0f pt", group: "Edge Glow"),
            .init("glowBlur", "Glow Blur", 0...30, 10, "Glow softness, points.", "%.0f pt", group: "Edge Glow"),
            .init("glowInset", "Inset", 0...30, 0, "Pulled in from the container's edge, points.", "%.0f pt", group: "Edge Glow"),
            .init("glowSpin", "Palette Spin", -2...2, 0.6, "The palette running round the edge, turns per ~6 s.", group: "Edge Glow"),
            .init("glowPulse", "Breathe", 0...1, 0.3, "Idle pulsing of the glow.", group: "Edge Glow"),
            .init("tracerSpeed", "Tracer Speed", 0...3, 1, "Laps per ~4 s.", group: "Edge Glow"),
            .init("tracerTrail", "Trail", 0.02...0.6, 0.22, "Trail length, as a fraction of the perimeter.", group: "Edge Glow"),
            .init("tracers", "Tracers", 1...4, 1, "How many run round.", "%.0f", group: "Edge Glow"),
            .init("tracerWidth", "Tracer Width", 1...12, 3, "Line width, points.", "%.0f pt", group: "Edge Glow"),
            .init("tracerGlow", "Tracer Glow", 0...2, 1, "Halo on the tracer."),
            .init("glowColor", "Colour", 0...1, 0, "The palette sweeping round, or the primary colour only.", "%.0f", group: "Edge Glow", choices: ["Palette", "Primary"]),
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
        case .symbols: return [
            .init("effect", "Effect", 0...5, 0, "Apple's symbol effect.", "%.0f", choices: ["Bounce", "Pulse", "Variable", "Wiggle", "Breathe", "Rotate"]),
            .init("size", "Size", 0.2...0.8, 0.45, "Glyph as a fraction of the disc."),
            .init("hold", "Hold", 0.5...6, 2, "Seconds before the glyph is replaced with the next.", "%.1f s"),
            .init("continuous", "Effect", 0...1, 1, "Fires once on each replace, or runs continuously.", "%.0f", choices: ["Once", "Continuous"]),
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
            .init("tint", "Colour", 0...1, 0, "White, or the palette.", "%.0f", choices: ["White", "Palette"]),
        ]
        case .tiles: return [
            .init("cell", "Tile", 8...80, 28, "Tile size, points.", "%.0f pt"),
            .init("bulge", "Bulge", 0...1.5, 0.6, "How much each tile bends what’s behind it."),
            .init("frost", "Frost", 0...1, 0.35, "Haze and scatter."),
            .init("grout", "Grout", 0...1, 0.6, "The lines between tiles."),
            .init("coverage", "Coverage", 0...1, 1, "How much of the width the panel covers, from the right."),
            .init("orientation", "Pattern", 0...2, 0, "Square tiles, or reeded flutes.", "%.0f", choices: ["Tiles", "Vertical", "Horizontal"]),
        ]
        case .bubble: return [
            .init("thickness", "Film", 0...2, 0.8, "Film thickness — how many colour cycles across."),
            .init("drain", "Drain", 0...2, 0.6, "Film draining downward over time."),
            .init("iridescence", "Iridescence", 0...2, 1, "The film's colour strength."),
            .init("rim", "Rim", 0...2, 1, "The bright edge."),
            .init("pool", "Pool", 0...2, 0.8, "Glow gathering at the bottom."),
            .init("highlight", "Highlights", 0...2, 1, "The two specular hits."),
            .init("wobble", "Wobble", 0...1, 0.5, "The bubble is never quite round."),
            .init("shell", "Shell", 0...1, 0, "Thickens the rim into a glass wall with its own inner edge, bands sliding round it — the thick purple bubble."),
            .init("floor", "Floor Glow", 0...1, 0, "A lit floor beneath."),
            .init("bandSpeed", "Band Speed", 0...3, 1, "How fast the film's bands slide."),
            .init("bands", "Bands", 1...8, 3, "Bands round the shell.", "%.0f"),
        ]
        case .slices: return [
            .init("slats", "Slats", 6...60, 22, "Slices across.", "%.0f"),
            .init("duty", "Width", 0.2...0.95, 0.55, "Slat width as a fraction of the pitch."),
            .init("wobble", "Wobble", 0...1, 0.3, "Slat widths breathing."),
            .init("moire", "Moiré", 0...1, 0.5, "The fine ring pattern inside each slat."),
            .init("tilt", "Tilt", -0.6...0.6, 0, "Slat angle, radians."),
            .init("reflect", "Reflection", 0...1, 0.8, "The squashed reflection below."),
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
            .init("multiply", "Blend", 0...1, 0, "Add is light; multiply is ink on paper.", "%.0f", choices: ["Add", "Multiply"]),
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
            .init("mode", "Mode", 0...1, 0, "The gratings' form.", "%.0f", choices: ["Rings", "Lines"]),
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
        case .frostOrb: return [
            .init("blobs", "Blobs", 1...8, 3, "Colour sources inside.", "%.0f"),
            .init("blur", "Blur", 0...1, 0.3, "How soft the colour is."),
            .init("frost", "Frost", 0...1, 0.55, "The milky shell."),
            .init("rim", "Rim", 0...2, 1, "Edge definition against a white ground."),
            .init("shadow", "Shadow", 0...1, 0.6, "The soft shadow beneath."),
            .init("drift", "Drift", 0...2, 0.6, "How fast the colour moves."),
            .init("saturation", "Saturation", 0...1.5, 1, "Colour strength."),
            .init("core", "Core Glow", 0...1, 0, "Lit from inside, brighter with audio."),
        ]
        case .globe: return [
            .init("level", "Level", 0...1, 0.45, "How full. Audio adds to it."),
            .init("wave", "Wave", 0...1, 0.5, "Surface height."),
            .init("speed", "Wave Speed", 0...3, 1, "Surface motion."),
            .init("tint", "Tint", 0...1, 0.85, "Liquid colour strength."),
            .init("glass", "Glass", 0...2, 1, "Rim and Fresnel."),
            .init("tilt", "Tilt", -0.8...0.8, 0, "Rotation, radians."),
            .init("bubbles", "Bubbles", 0...1, 0.4, "Rising through the liquid."),
            .init("caustic", "Caustic", 0...2, 1, "The light under the surface."),
        ]
        case .silk: return [
            .init("fold", "Fold", 0...1, 0.5, "How creased the membrane is, and how far its edge wanders."),
            .init("speed", "Fold Speed", 0...2, 0.6, "How fast it moves."),
            .init("tint", "Tint", 0...1.5, 0.9, "Colour at the folds."),
            .init("rim", "Rim", 0...1.5, 0.8, "Colour at the edge."),
            .init("softness", "Softness", 0...1, 0.5, "Edge softness."),
        ]
        case .liquidRing: return [
            .init("width", "Width", 0.05...0.5, 0.16, "Band width as a fraction of the radius."),
            .init("turbulence", "Turbulence", 0...1, 0.5, "How much the edges move."),
            .init("flow", "Flow", 0...2, 0.6, "How fast the fluid runs round."),
            .init("heat", "Heat", 0...2, 0.6, "White-hot highlights."),
            .init("dots", "Dots", 0...1, 0.6, "The dot field inside."),
            .init("density", "Dot Density", 4...30, 14, "Rings of dots.", "%.0f"),
            .init("glow", "Inner Glow", 0...3, 1, "The palette glow inside the band."),
        ]
        case .tide: return [
            .init("level", "Level", 0.05...0.95, 0.5, "How full. Audio adds to it."),
            .init("tumble", "Tumble", 0...3, 1, "How fast ‘down’ turns. This is what gives the top / side / under views."),
            .init("wave", "Wave", 0...1.5, 0.6, "Surface height."),
            .init("density", "Density", 0...3, 1.2, "0 clear film (colour only at the surface), 3 milk."),
            .init("frost", "Frost", 0...1, 0.15, "Frosted glass in front of it."),
            .init("film", "Surface Film", 0...2, 1, "Thin-film colour where the surface is seen edge-on."),
            .init("highlight", "Highlights", 0...2, 1, "Specular on the surface and the underwater mirror."),
            .init("tilt", "Tilt", -1...1, 0.2, "A standing lean of ‘down’, radians."),
            .init("sheen", "Sheen", 0...2, 1, "The broad band of light the surface throws back — the gold sheet."),
            .init("glass", "Glass", 0...1, 0.3, "The empty part of the sphere: 0 clear, 1 white glass."),
            .init("shadow", "Shadow", 0...1, 0, "A soft shadow beneath, for a light ground."),
            .init("sway", "Sway", 0...1, 0.3, "A quicker rocking on top of the tumble."),
            .init("colorDepth", "Colour Depth", 0...1, 0.5, "How much the colour shifts along the palette with thickness."),
        ]
        case .droplet: return [
            .init("sag", "Sag", 0...1, 0.6, "Heavier at the bottom."),
            .init("wobble", "Wobble", 0...1, 0.5, "Surface-tension modes."),
            .init("refraction", "Refraction", 0...1.5, 0.7, "How much it bends what’s behind."),
            .init("tint", "Tint", 0...1, 0.7, "How much palette shows through."),
            .init("highlight", "Highlights", 0...2, 1, "The window and the specular."),
        ]
        case .pour: return [
            .init("rate", "Cycle Rate", 0...2, 0.6, "Fill → hold → drain cycles. 0 holds at half."),
            .init("stream", "Stream", 0...1.5, 1, "The pouring column."),
            .init("ripples", "Ripples", 0...2, 1, "Where the stream lands."),
            .init("foam", "Foam", 0...1.5, 0.8, "The bright surface band."),
            .init("tint", "Tint", 0...1, 0.9, "Liquid colour strength."),
            .init("hold", "Hold", 0...1, 0.4, "How long it stays full."),
        ]
        case .pool: return [
            .init("drops", "Drops", 1...8, 4, "Drops landing.", "%.0f"),
            .init("speed", "Ring Speed", 0.2...3, 1, "How fast rings spread."),
            .init("width", "Ring Width", 0...1, 0.4, "Ring thickness."),
            .init("refraction", "Refraction", 0...2, 1, "How much the floor bends."),
            .init("caustic", "Caustic", 0...2, 1, "Bright slopes."),
            .init("calm", "Swell", 0...1, 0.5, "A slow background swell."),
        ]
        case .caustics: return [
            .init("scale", "Scale", 1...8, 3, "Web fineness."),
            .init("speed", "Speed", 0...3, 1, "Drift."),
            .init("sharpness", "Sharpness", 0...1, 0.5, "Line thinness."),
            .init("layers", "Layers", 1...3, 2, "Overlaid webs.", "%.0f"),
            .init("tint", "Tint", 0...1, 0.4, "Palette on the light; 0 is white."),
            .init("floor", "Floor", 0...1, 0.35, "The palette floor under the web."),
        ]
        case .lava: return [
            .init("blobs", "Blobs", 1...8, 5, "Blobs.", "%.0f"),
            .init("heat", "Heat", 0.1...3, 1, "Rise speed."),
            .init("size", "Size", 0.1...0.5, 0.17, "Blob radius."),
            .init("goo", "Goo", 0...1, 0.5, "How far apart they still merge."),
            .init("glow", "Glow", 0...1.5, 0.6, "Halo round each blob."),
            .init("stretch", "Stretch", 0...1, 0.7, "Elongation while moving."),
        ]
        case .jelly: return [
            .init("wobble", "Wobble", 0...1, 0.5, "Idle motion."),
            .init("springiness", "Springiness", 0.5...6, 2.5, "Mode frequency."),
            .init("translucency", "Translucency", 0...1, 0.5, "See-through-ness."),
            .init("core", "Core", 0...1.5, 0.8, "The lit centre."),
            .init("highlight", "Highlights", 0...2, 1, "Shell sheen and specular."),
            .init("modes", "Modes", 1...6, 3, "Spring modes.", "%.0f"),
        ]
        case .slick: return [
            .init("swirl", "Swirl", 0...2, 1, "Domain warp."),
            .init("scale", "Scale", 0.5...4, 1.5, "Pattern size."),
            .init("iridescence", "Iridescence", 0.2...2, 1, "Colour cycles."),
            .init("speed", "Speed", 0...3, 1, "Motion."),
            .init("contrast", "Contrast", 0...1, 0.5, "Band sharpness."),
            .init("water", "Water", 0...2, 1, "The dark surface beneath."),
        ]
        case .deep: return [
            .init("rays", "Rays", 0...2, 1, "Light shafts."),
            .init("motes", "Motes", 0...2, 1, "Drifting specks."),
            .init("depth", "Depth", 0...1, 0.8, "How dark it gets below."),
            .init("surface", "Surface", 0...2, 1, "The caustic web up top."),
            .init("sway", "Sway", 0...1, 0.5, "The light source moving."),
        ]
        case .nebula: return [
            .init("density", "Density", 0...3, 1.2, "Cloud thickness."),
            .init("scale", "Scale", 0.5...4, 1.6, "Cloud feature size."),
            .init("flow", "Flow", 0...3, 1, "Drift."),
            .init("glow", "Glow", 0...1.5, 0.5, "Self-light."),
            .init("shell", "Shell", 0...1.5, 0.8, "The glass round it."),
            .init("light", "Lighting", 0...1, 0.7, "Directional shading of the cloud."),
        ]
        case .thinkingOrbs: return [
            .init("state", "State", 0...8, 0, "What the agent is doing.", "%.0f", group: "State",
                  choices: ["Working", "Searching", "Solving", "Listening", "Connecting", "Weaving", "Composing", "Breathing", "Shaping"]),
            .init("count", "Dots", 12...200, 81, "Dots.", "%.0f", group: "Dots"),
            .init("dotSize", "Dot Size", 0.5...8, 2.4, "Points.", "%.1f pt", group: "Dots"),
            .init("colour", "Colour", 0...2, 0, "White, the palette, or the primary.", "%.0f", group: "Dots", choices: ["White", "Palette", "Primary"]),
            .init("orbits", "Orbit Paths", 0...1, 0.5, "Faint rings under Working and Weaving.", group: "Effect"),
            .init("particles", "Particles", 0...8, 3, "Brighter sparkles drifting through.", "%.0f", group: "Effect"),
        ]
        case .orbKit: return [
            .init("state", "State", 0...8, 0, "What the agent is doing.", "%.0f", group: "State",
                  choices: ["Working", "Searching", "Solving", "Listening", "Connecting", "Weaving", "Composing", "Breathing", "Shaping"]),
            .init("size", "Size", 0...1, 0, "Their two tuned presets, drawn at the stage's size.", "%.0f", group: "Size", choices: ["64px", "20px"]),
            .init("speed", "Speed", 0.1...3, 1, "Multiplier on the preset's speed.", "%.1f×", group: "Motion"),
            .init("theme", "Theme", 0...2, 0, "Follows the stage, or fixed.", "%.0f", group: "Theme", choices: ["Auto", "Dark", "Light"]),
        ]
        case .beamKit: return [
            .init("family", "Family", 0...1, 0, "A travelling beam, or a breathing glow.", "%.0f", group: "Family", choices: ["Rotate", "Pulse"]),
            .init("type", "Type", 0...2, 0, "Rotate: large / small / line. Pulse: outside / inner (the third is inner).", "%.0f", group: "Type", choices: ["Large", "Small", "Line"]),
            .init("variant", "Color theme", 0...3, 0, "Their four variants.", "%.0f", group: "Color theme", choices: ["Colorful", "Mono", "Ocean", "Sunset"]),
            .init("theme", "Theme", 0...2, 0, "Follows the stage, or fixed.", "%.0f", group: "Color theme", choices: ["Auto", "Dark", "Light"]),
            .init("duration", "Duration", 0...8, 0, "Seconds per lap. 0 keeps the preset.", "%.2f s", group: "Motion"),
            .init("strength", "Strength", 0...2, 1, "Overall intensity.", "%.0f%%", group: "Glow styling"),
            .init("radius", "Corner radius", 0...40, 16, "Points.", "%.0f pt", group: "Glow styling"),
            .init("size", "Size", 0.5...2, 1, "Glow boost — the pulse family's blob size.", "%.2f×", group: "Glow styling"),
            .init("brightness", "Brightness", 0.5...2.5, 1.3, "The outward glow.", "%.1f×", group: "Glow styling"),
            .init("saturation", "Saturation", 0.5...2.5, 1.2, "The outward glow.", "%.1f×", group: "Glow styling"),
            .init("stroke", "Stroke", 0...2, 1, "The tight ring.", "%.1f×", group: "Glow styling"),
            .init("inner", "Inner glow", 0...2, 1, "The inward wash.", "%.1f×", group: "Glow styling"),
            .init("bloom", "Bloom", 0...2, 1, "The wide halo.", "%.1f×", group: "Glow styling"),
            .init("hueRange", "Hue range", 0...180, 30, "Degrees of hue the beam spans.", "%.0f°", group: "Glow styling"),
        ]
        case .gooey: return [
            .init("effect", "Effect", 0...3, 0, "How the items come out.", "%.0f", group: "Effect", choices: ["Morph", "Move", "Bend", "Melt"]),
            .init("blur", "Goo blur", 0...20, 6, "The blur that makes shapes merge, points.", "%.0f", group: "Effect settings"),
            .init("contrast", "Contrast", 4...40, 18, "How hard the merged edge is.", "%.0f", group: "Effect settings"),
            .init("waviness", "Waviness", 0...10, 0, "Wobble on the shapes' edges.", "%.0f", group: "Effect settings"),
            .init("fill", "Button fill color", 0...4, 1, "The goo's colour.", "%.0f", group: "Button fill color", choices: ["Dark", "Light", "Blue", "Peach", "Palette"]),
            .init("items", "Items", 1...6, 3, "Buttons that come out.", "%.0f", group: "Component animation"),
            .init("openDuration", "Open duration", 100...1500, 550, "Milliseconds.", "%.0f ms", group: "Component animation"),
            .init("closeDuration", "Close duration", 100...1500, 250, "Milliseconds.", "%.0f ms", group: "Component animation"),
            .init("openStagger", "Open stagger", 0...200, 40, "Per item, milliseconds.", "%.0f ms", group: "Component animation"),
            .init("closeStagger", "Close stagger", 0...200, 0, "Per item, milliseconds.", "%.0f ms", group: "Component animation"),
            .init("spread", "Spread", 0.5...2, 1, "How far the items travel.", "%.1f×", group: "Component animation"),
            .init("anticipation", "Anticipation", 0...20, 5, "A pull back before the move, points.", "%.0f pt", group: "Component animation"),
            .init("anticipationDuration", "Anticipation duration", 0...1500, 700, "Milliseconds.", "%.0f ms", group: "Component animation"),
            .init("iconFade", "Icon fade", 0...600, 180, "Milliseconds.", "%.0f ms", group: "Component animation"),
            .init("iconDelay", "Icon delay", 0...600, 120, "Milliseconds.", "%.0f ms", group: "Component animation"),
            .init("auto", "Advance", 0...1, 1, "On the clock, or only on tap.", "%.0f", group: "Component animation", choices: ["Tap", "Auto"]),
        ]
        case .metal: return [
            .init("type", "Type", 0...3, 0, "What wears the metal.", "%.0f", group: "Type", choices: ["Circle button", "Button", "Text", "Badge"]),
            .init("color", "Color", 0...2, 0, "The metal.", "%.0f", group: "Color", choices: ["Chromatic", "Silver", "Gold"]),
            .init("strength", "Strength", 0...1, 0.81, "How metallic.", "%.0f%%", group: "Metal effect styling"),
            .init("scale", "Shader scale", 0.3...3, 1.3, "Band density.", "%.1f×", group: "Metal effect styling"),
            .init("ring", "Ring width", 1...8, 2, "Points.", "%.0f pt", group: "Metal effect styling"),
            .init("innerShadow", "Inner shadow", 0...2, 1, "Inside the ring.", "%.1f×", group: "Metal effect styling"),
            .init("glow", "Intensity", 0...4, 2, "Glow on hover.", "%.0f×", group: "Glow"),
            .init("appear", "Appear", 50...1000, 300, "Milliseconds.", "%.0f ms", group: "Glow"),
            .init("disappear", "Disappear", 50...1500, 450, "Milliseconds.", "%.0f ms", group: "Glow"),
            .init("bend", "Strength", 0...2, 0.74, "How much the surface dents toward the pointer.", "%.2f×", group: "Cursor bend"),
            .init("reach", "Reach", 0...120, 36, "Points.", "%.0f pt", group: "Cursor bend"),
            .init("dent", "Max dent", 0...30, 9, "Points.", "%.0f pt", group: "Cursor bend"),
            .init("rDistance", "Distance", 20...400, 186, "How far the reflection is felt, points.", "%.0f pt", group: "Cursor reflection"),
            .init("rSpecular", "Specular", 0.5...10, 3.35, "Highlight tightness.", "%.2f", group: "Cursor reflection"),
            .init("rFalloff", "Falloff", 0...120, 37, "Points before it starts fading.", "%.0f pt", group: "Cursor reflection"),
            .init("rReach", "Reach", 0...40, 11.5, "Highlight strength.", "%.1f", group: "Cursor reflection"),
            .init("optGlow", "Glow", 0...1, 1, "", "%.0f", group: "Options", choices: ["Off", "On"]),
            .init("optReflection", "Reflection", 0...1, 1, "", "%.0f", group: "Options", choices: ["Off", "On"]),
            .init("optShadow", "Inner shadow", 0...1, 1, "", "%.0f", group: "Options", choices: ["Off", "On"]),
            .init("optBend", "Bend", 0...1, 1, "", "%.0f", group: "Options", choices: ["Off", "On"]),
        ]
        case .water: return [
            .init("amount", "Amount", 0...30, 8, "Refraction, points.", "%.0f pt"),
            .init("scale", "Scale", 20...300, 90, "Ripple size, points.", "%.0f pt"),
            .init("speed", "Speed", 0...3, 1, "Ripple motion."),
            .init("caustic", "Caustic", 0...2, 0.8, "Brightening on the slopes."),
        ]
        case .haze: return [
            .init("amount", "Amount", 0...1, 0.4, "Veil strength."),
            .init("scale", "Scale", 0.5...6, 2, "Fog patch size."),
            .init("breathe", "Breathe", 0...1, 0.5, "Slow pulsing."),
        ]
        case .fizz: return [
            .init("count", "Bubbles", 1...40, 16, "Bubbles.", "%.0f"),
            .init("speed", "Speed", 0.2...3, 1, "Rise speed."),
            .init("size", "Size", 2...16, 6, "Bubble radius, points.", "%.0f pt"),
        ]
        case .glints: return [
            .init("threshold", "Threshold", 0...1, 0.75, "How bright a point must be to sparkle."),
            .init("length", "Length", 4...80, 30, "Streak length, points.", "%.0f pt"),
            .init("strength", "Strength", 0...3, 1, "Streak brightness."),
            .init("rotate", "Rotate", -2...2, 0.2, "Streak spin, radians per second."),
        ]
        case .parallax: return [
            .init("offset", "Offset", 0...30, 8, "Depth, points.", "%.0f pt"),
            .init("angle", "Angle", 0...6.28, 0.8, "Light direction, radians."),
            .init("shadow", "Shadow", 0...1, 0.5, "The dark copy."),
            .init("light", "Light", 0...1, 0.5, "The light copy."),
            .init("soften", "Soften", 0...12, 4, "Shadow blur, points.", "%.0f pt"),
        ]
        case .focus: return [
            .init("x", "Focus X", 0...1, 0.5, "Focal point, across."),
            .init("y", "Focus Y", 0...1, 0.5, "Focal point, down."),
            .init("radius", "Blur", 0...40, 14, "Maximum blur, points.", "%.0f pt"),
            .init("band", "Focus", 0...1, 0, "A point, or a horizontal band (tilt-shift).", "%.0f", choices: ["Point", "Band"]),
            .init("falloff", "Falloff", 0.5...4, 1.6, "How quickly it goes soft away from focus."),
            .init("bokeh", "Bokeh", 0...1, 0.6, "Highlights kept as discs."),
            .init("drift", "Drift", 0...1, 0, "The focal point wanders."),
        ]
        case .buttonGlow: return [
            .init("width", "Glow Width", 2...40, 14, "Points.", "%.0f pt"),
            .init("blur", "Blur", 0...30, 12, "Softness, points.", "%.0f pt"),
            .init("rotate", "Rotate", -2...2, 0.5, "Palette running round the edge."),
            .init("breathe", "Breathe", 0...1, 0.5, "Idle pulse."),
            .init("buttons", "Buttons", 1...3, 2, "How many controls to show.", "%.0f"),
            .init("orb", "Orb Size", 0.1...0.4, 0.2, "The orb beside them, as a fraction of width."),
        ]
        case .sheet: return [
            .init("height", "Height", 0.4...1, 0.72, "Sheet height as a fraction of the screen."),
            .init("hero", "Hero Size", 0.15...0.6, 0.3, "The orb at the top, as a fraction of width."),
            .init("waveform", "Waveform", 0...1, 1, "A waveform in the input bar.", "%.0f"),
            .init("dim", "Dim", 0...1, 0.5, "How much the app dims behind."),
        ]
        case .hold: return [
            .init("orbListening", "Listening", 0...8, 3, "Their orb's verb while held.", "%.0f", group: "Orb states (when the hero is Thinking Orbs)", choices: LabExperiment.orbVerbs),
            .init("orbSpeaking", "Speaking", 0...8, 6, "Their orb's verb after release.", "%.0f", group: "Orb states (when the hero is Thinking Orbs)", choices: LabExperiment.orbVerbs),
            .init("grow", "Grow Time", 0.2...2, 0.7, "Seconds of hold to reach full screen.", "%.1f s"),
            .init("spring", "Spring", 0.2...1.2, 0.45, "Response."),
            .init("bounce", "Bounce", 0...1, 0.2, "Damping headroom."),
            .init("talk", "Talk Time", 1...8, 3, "Seconds it talks after release before settling.", "%.1f s"),
            .init("hero", "Hero Size", 0.3...0.9, 0.55, "Full-screen orb, as a fraction of width."),
            .init("glow", "Edge Glow", 0...1, 0.8, "Edge glow while listening."),
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
            .init("orbPod", "In the pod", 0...8, 7, "Their orb's verb in the tab bar.", "%.0f", group: "Orb states (when the hero is Thinking Orbs)", choices: LabExperiment.orbVerbs),
            .init("orbChat", "In chat", 0...8, 0, "Their orb's verb in the chat sheet.", "%.0f", group: "Orb states (when the hero is Thinking Orbs)", choices: LabExperiment.orbVerbs),
            .init("orbVoice", "In voice", 0...8, 3, "Their orb's verb full screen.", "%.0f", group: "Orb states (when the hero is Thinking Orbs)", choices: LabExperiment.orbVerbs),
            .init("hold", "Hold", 1...8, 3, "Seconds per stage when cycling.", "%.1f s"),
            .init("auto", "Advance", 0...1, 1, "On the clock, or only on tap.", "%.0f", choices: ["Tap", "Auto"]),
            .init("spring", "Spring", 0.2...1.2, 0.5, "Response — lower is snappier."),
            .init("bounce", "Bounce", 0...1, 0.15, "Damping headroom."),
            .init("sheet", "Sheet Height", 0.4...0.95, 0.72, "The chat sheet, as a fraction of the screen."),
            .init("role", "Ring Role", 0...2, 2, "Where the orb lives in the chat sheet.", "%.0f", choices: ["Hero", "Avatar", "Input"]),
            .init("hero", "Hero Size", 0.3...0.9, 0.55, "The ring in the voice stage, as a fraction of screen width."),
            .init("glow", "Edge Glow", 0...1, 0.7, "Edge glow in the voice stage."),
            .init("dim", "Dim", 0...1, 0.6, "How much the app dims behind the sheet."),
        ]
        case .agentStates: return [
            .init("orbIdle", "Idle", 0...8, 7, "Their orb's verb while idle.", "%.0f", group: "Orb states (when the hero is Thinking Orbs)", choices: LabExperiment.orbVerbs),
            .init("orbListening", "Listening", 0...8, 3, "Their orb's verb while listening.", "%.0f", group: "Orb states (when the hero is Thinking Orbs)", choices: LabExperiment.orbVerbs),
            .init("orbThinking", "Thinking", 0...8, 0, "Their orb's verb while thinking.", "%.0f", group: "Orb states (when the hero is Thinking Orbs)", choices: LabExperiment.orbVerbs),
            .init("orbSpeaking", "Speaking", 0...8, 6, "Their orb's verb while speaking.", "%.0f", group: "Orb states (when the hero is Thinking Orbs)", choices: LabExperiment.orbVerbs),
            .init("hold", "Hold", 0.5...8, 2.5, "Seconds per state when cycling.", "%.1f s", group: "Motion"),
            .init("auto", "Advance", 0...1, 1, "On the clock, or only on tap.", "%.0f", choices: ["Tap", "Auto"]),
            .init("breath", "Idle Breath", 0...0.2, 0.05, "Idle scale swing."),
            .init("open", "Listen Open", 0...0.6, 0.25, "How much the ring opens when listening."),
            .init("orbit", "Think Orbit", 0.5...4, 1.6, "Thinking comet speed."),
            .init("pulse", "Speak Pulse", 0...0.5, 0.2, "Speaking scale swing per syllable."),
            .init("spring", "Spring", 0.2...1.2, 0.45, "Transition response."),
        ]
        case .waveform: return [
            .init("style", "Style", 0...2, 0, "The waveform's form.", "%.0f", choices: ["Bars", "Line", "Ring"]),
            .init("bars", "Bars", 8...96, 32, "Segments.", "%.0f"),
            .init("height", "Height", 0.1...1, 0.5, "Peak height as a fraction of the area."),
            .init("thickness", "Thickness", 1...12, 4, "Bar or line width, points.", "%.0f pt"),
            .init("smooth", "Smoothing", 0...1, 0.5, "How much neighbours share energy."),
            .init("mirror", "Mirror", 0...1, 1, "Symmetric about the middle.", "%.0f", choices: ["Off", "On"]),
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
        case .sunflower: return [
            .init("spacing", "Density", 6...24, 10, "Seed spacing, points — the spiral’s scale.", "%.0f pt", group: "Field"),
            .init("dot", "Dot Size", 1...8, 2.6, "Points, at the centre.", "%.1f pt", group: "Field"),
            .init("growth", "Edge Growth", 0...1.5, 0.7, "How much bigger the dots get toward the edge.", group: "Field"),
            .init("centerX", "Centre X", 0...1, 0.42, "The spiral’s centre across the screen.", group: "Field"),
            .init("centerY", "Centre Y", 0...1, 0.52, "The spiral’s centre down the screen.", group: "Field"),
            .init("breathe", "Breathe", 0...1, 0.4, "Idle pulsing of the whole field.", group: "Field"),
            .init("ground", "Ground", 0...2, 0, "White like the original, or dark, or the stage’s.", "%.0f", group: "Field", choices: ["Stage", "Light", "Dark"]),
            .init("rate", "Rate", 0...3, 1.2, "Blooms per second, on the clock.", "%.1f /s", group: "Blooms"),
            .init("life", "Life", 1...10, 4, "Seconds a bloom lives.", "%.1f s", group: "Blooms"),
            .init("radius", "Radius", 40...300, 130, "Points, fully open.", "%.0f pt", group: "Blooms"),
            .init("grow", "Dot Growth", 0...3, 1.4, "How much a bloom swells the dots under it.", "%.1f×", group: "Blooms"),
            .init("tint", "Colour", 0...1, 1, "How far the dots take the bloom’s colour.", group: "Blooms"),
            .init("core", "Core", 0...1, 0.6, "A brighter centre to each bloom.", group: "Blooms"),
            .init("wave", "Ripple", 0...3, 1.2, "A ring from the centre whose height is the voice.", "%.1f×", group: "Voice"),
            .init("waveSpeed", "Ripple Speed", 20...400, 140, "Points per second.", "%.0f pt/s", group: "Voice"),
            .init("spawn", "Bloom on Beat", 0...1, 1, "A new bloom where the voice lands.", "%.0f", group: "Voice", choices: ["Off", "On"]),
            .init("threshold", "Threshold", 0.05...0.8, 0.35, "How loud before a bloom opens.", group: "Voice"),
            .init("hero", "Hero", 0...1, 0, "The hero orb at the spiral’s centre, or the field alone.", "%.0f", group: "Hero", choices: ["Off", "On"]),
            .init("heroSize", "Hero Size", 0.2...0.7, 0.4, "As a fraction of the width.", group: "Hero"),
            .init("transcript", "Transcript", 0...1, 1, "Words at the bottom as you speak — sample copy until the mic is on.", "%.0f", group: "Transcript", choices: ["Off", "On"]),
            .init("textSize", "Text Size", 14...28, 20, "Points.", "%.0f pt", group: "Transcript"),
            .init("textGlow", "Glow", 0...1, 0.4, "On each arriving word.", group: "Transcript"),
        ]
        case .system: return [
            .init("hold", "Hold", 0.5...8, 2.5, "Seconds in each step when advancing on the clock.", "%.1f s", group: "Play"),
            .init("auto", "Advance", 0...1, 1, "On the clock, or only on tap.", "%.0f", group: "Play", choices: ["Tap", "Auto"]),
            .init("spring", "Spring", 0.2...1.2, 0.55, "Response of the morph between surfaces.", group: "Play"),
            .init("bounce", "Bounce", 0...1, 0.2, "Damping headroom.", group: "Play"),
            .init("talk", "Talk Time", 1...8, 3, "Seconds it speaks after a hold is released.", "%.1f s", group: "Play"),
            .init("chrome", "Labels", 0...1, 1, "The step name and hint over the phone.", "%.0f", group: "Play", choices: ["Off", "On"]),
        ]
        case .caption: return [
            .init("style", "Style", 0...2, 1, "How words arrive.", "%.0f", choices: ["Fade", "Blur in", "Typed"]),
            .init("rate", "Words / s", 1...12, 4, "Arrival rate.", "%.0f"),
            .init("size", "Size", 14...44, 24, "Type size.", "%.0f pt"),
            .init("glow", "Glow", 0...1, 0.4, "Glow behind the newest words."),
            .init("hold", "Hold", 1...10, 4, "Seconds a sentence stays before the next.", "%.1f s"),
        ]
        case .sphere: return [
            .init("shape", "Shape", 0...2, 0, "The gradient source.", "%.0f", choices: ["Star", "Blob", "Ring"]),
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

/// One state of the Morph: what shape the glass takes, and what rides
/// on it.
public enum LabMorphKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case pod, pill, card, sheet, fullScreen
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .pod: return "Pod"
        case .pill: return "Pill"
        case .card: return "Card"
        case .sheet: return "Sheet"
        case .fullScreen: return "Full Screen"
        }
    }
}

/// A UI animation a state can carry — the pieces of the hidden UI labs.
public enum LabMorphAdornment: String, CaseIterable, Identifiable, Codable, Sendable {
    case edgeGlow, borderBeam, waveform, caption, transcript
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .edgeGlow: return "Edge Glow"
        case .borderBeam: return "Border Beam"
        case .waveform: return "Waveform"
        case .caption: return "Caption"
        case .transcript: return "Transcript"
        }
    }
    public var symbol: String {
        switch self {
        case .edgeGlow: return "iphone.gen3.radiowaves.left.and.right"
        case .borderBeam: return "shippingbox"
        case .waveform: return "waveform"
        case .caption: return "text.bubble"
        case .transcript: return "text.quote"
        }
    }
}

/// How a state's content and adornments arrive and leave. The glass
/// panel itself always morphs on the spring; this is what rides on it.
public enum LabMorphTransition: String, CaseIterable, Identifiable, Codable, Sendable {
    case none, fade, grow, slide, flare
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .none: return "Cut"
        case .fade: return "Fade"
        case .grow: return "Grow"
        case .slide: return "Slide up"
        case .flare: return "Flare"
        }
    }
    public var summary: String {
        switch self {
        case .none: return "Appears at once."
        case .fade: return "Fades in over the transition time."
        case .grow: return "Scales up from small, fading in."
        case .slide: return "Rises from below, fading in."
        case .flare: return "Fades in, and the edge glow flares bright then settles — light announcing the state."
        }
    }
}

public struct LabMorphState: Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var kind: LabMorphKind
    public var adornments: Set<LabMorphAdornment> = []
    public var enter: LabMorphTransition = .fade
    public var exit: LabMorphTransition = .fade
    public init(_ kind: LabMorphKind, _ adornments: Set<LabMorphAdornment> = []) {
        self.kind = kind
        self.adornments = adornments
    }
}

/// The Lab's three rooms (Chris, 2026-09-15): what the thing is, what
/// it sits in, and what a touch does.
public enum LabSection: String, CaseIterable, Identifiable, Sendable {
    case orb, ui, flows, system
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .orb: return "Orb"
        case .ui: return "UI"
        case .flows: return "Flows"
        case .system: return "System"
        }
    }
    public var caption: String {
        switch self {
        case .orb: return "What lives in the circle. Bases, and post effects that stack over any of them."
        case .ui: return "The surfaces it sits in — buttons, the sheet, the screen’s edge."
        case .flows: return "What a touch does — tap, hold, listen, talk."
        case .system: return "The product, assembled: a look for every slot, played end to end."
        }
    }
    public var symbol: String {
        switch self {
        case .orb: return "circle.fill"
        case .ui: return "rectangle.on.rectangle"
        case .flows: return "hand.tap"
        case .system: return "square.grid.2x2"
        }
    }
    public var experiments: [LabExperiment] { LabExperiment.allCases.filter { $0.section == self && !$0.isHidden } }
    /// Orb splits into bases and post effects.
    public var bases: [LabExperiment] { experiments.filter { !$0.decoratesRing } }
    public var posts: [LabExperiment] { experiments.filter { $0.decoratesRing } }
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
    case bloom, rays, ripple, refraction, chromatic, kaleido, dots, grain, glitch, crt, neon, frost, duotone, spin, tiles, chrome, water, haze, fizz, glints, parallax, focus
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
        case .water: return .water
        case .haze: return .haze
        case .fizz: return .fizz
        case .glints: return .glints
        case .parallax: return .parallax
        case .focus: return .focus
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
    /// A heading the panel groups consecutive knobs under. `nil` for
    /// experiments with one list.
    public let group: String?
    /// For an enumerated knob: the label of each integer value from the
    /// range's lower bound up. The panel draws chips instead of a slider
    /// — a segmented control, because these switch what is displayed.
    public let choices: [String]?

    public init(_ id: String, _ name: String, _ range: ClosedRange<Double>, _ defaultValue: Double, _ help: String, _ format: String = "%.2f", group: String? = nil, choices: [String]? = nil) {
        self.id = id
        self.name = name
        self.range = range
        self.defaultValue = defaultValue
        self.help = help
        self.format = format
        self.group = group
        self.choices = choices
    }

    /// A two-way knob — the panel draws a toggle.
    public var isToggle: Bool { choices?.count == 2 && range == 0...1 }
}

/// Named knob sets per experiment, kept in UserDefaults — the earmark
/// from 2026-09-14. A preset is the experiment's knobs plus its post
/// stack and hero, which is what "that look" means.
@MainActor
public final class LabPresetStore: ObservableObject {
    public struct Preset: Codable, Identifiable, Equatable {
        public var id = UUID()
        public var name: String
        public var experiment: String
        public var values: [String: Double]
        public var post: [String]
        public var hero: String?
        public var palette: String
    }
    @Published public private(set) var presets: [Preset] = []
    private let key = "nexus.lab.presets"

    public init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Preset].self, from: data) { presets = decoded }
    }

    public func presets(for e: LabExperiment) -> [Preset] { presets.filter { $0.experiment == e.id } }

    public func save(_ name: String, from lab: LabState) {
        let e = lab.experiment
        let prefix = e.id + "."
        var values = lab.values.filter { $0.key.hasPrefix(prefix) }
        for post in lab.post { for (k, v) in lab.values where k.hasPrefix(post.experiment.id + ".") { values[k] = v } }
        presets.removeAll { $0.experiment == e.id && $0.name == name }
        presets.append(Preset(name: name, experiment: e.id, values: values, post: lab.post.map(\.rawValue), hero: lab.hero?.rawValue, palette: lab.palette.rawValue))
        persist()
    }

    public func apply(_ preset: Preset, to lab: LabState) {
        lab.resetParameters(of: lab.experiment)
        for (k, v) in preset.values { lab.values[k] = v }
        lab.post = preset.post.compactMap(LabPostEffect.init(rawValue:))
        lab.hero = preset.hero.flatMap(LabExperiment.init(rawValue:))
        if let p = LabPalette(rawValue: preset.palette) { lab.palette = p }
    }

    public func delete(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(presets) { UserDefaults.standard.set(data, forKey: key) }
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
    /// Run speech recognition on the mic, for the transcript flows.
    @Published public var transcribe: Bool = false
    @Published public var palette: LabPalette = .nexus
    /// Post effects, in the order they are applied.
    @Published public var post: [LabPostEffect] = []
    /// Show the experiment at pod size in a glass pod, in the corner.
    @Published public var showPod: Bool = true
    /// In the pod preview, draw the experiment across the whole 62pt pod
    /// rather than the ring's 34pt-in-62 proportion. On by default —
    /// whatever ships will fill the circle (Chris, 2026-09-15).
    @Published public var podFill: Bool = true
    /// An SF Symbol drawn inside Orb, Refraction and Liquid — the glyph
    /// state of the pod, inside the effect. Empty for none.
    @Published public var glyph: String = ""
    /// Continuous hue rotation of the palette, degrees per second.
    @Published public var hueDrift: Double = 0
    /// 0 draws each experiment at its natural size; 1 scales it so its
    /// content fills the disc. On by default — the pod is the circle.
    @Published public var fill: Double = 1
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

    /// The Morph's states, in order. Add, remove, adorn.
    @Published public var morphStates: [LabMorphState] = [LabMorphState(.pod), LabMorphState(.pill), LabMorphState(.card), LabMorphState(.sheet)]

    public func addMorphState(_ kind: LabMorphKind) { morphStates.append(LabMorphState(kind)) }
    public func removeMorphState(_ id: UUID) { morphStates.removeAll { $0.id == id } }
    public func toggle(_ adornment: LabMorphAdornment, on id: UUID) {
        guard let i = morphStates.firstIndex(where: { $0.id == id }) else { return }
        if morphStates[i].adornments.contains(adornment) { morphStates[i].adornments.remove(adornment) }
        else { morphStates[i].adornments.insert(adornment) }
    }
    /// On every state, or off every state.
    public func setEnter(_ t: LabMorphTransition, on id: UUID) {
        if let i = morphStates.firstIndex(where: { $0.id == id }) { morphStates[i].enter = t }
    }
    public func setExit(_ t: LabMorphTransition, on id: UUID) {
        if let i = morphStates.firstIndex(where: { $0.id == id }) { morphStates[i].exit = t }
    }
    public func setAllTransitions(enter: LabMorphTransition?, exit: LabMorphTransition?) {
        for i in morphStates.indices {
            if let enter { morphStates[i].enter = enter }
            if let exit { morphStates[i].exit = exit }
        }
    }

    public func setAll(_ adornment: LabMorphAdornment, on: Bool) {
        for i in morphStates.indices {
            if on { morphStates[i].adornments.insert(adornment) } else { morphStates[i].adornments.remove(adornment) }
        }
    }

    /// The pointer over the stage, in the experiment's own coordinates
    /// (points from its centre), or nil — hover on the Mac, touch on the
    /// phone. For Metal's bend and reflection.
    @Published public var pointer: CGPoint? = nil

    /// The System's working spec — every slot's assignment. Autosaved,
    /// so the board survives a relaunch; named copies live in
    /// `LabSpecStore`.
    @Published public var spec: LabSpec = LabSpecStore.loadCurrent() {
        didSet { LabSpecStore.autosave(spec) }
    }

    /// Press-and-hold, for the Hold flow: when the press began, or nil.
    @Published public var holdStart: Date? = nil
    /// When the last hold ended — the flow's "talking" runs from here.
    @Published public var holdEnd: Date = .distantPast

    public init() {}

    public func beginHold() { if holdStart == nil { holdStart = Date() } }
    public func endHold() { if holdStart != nil { holdStart = nil; holdEnd = Date() } }

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
    /// See `LabState.fill`.
    public var fill: Double = 1
    /// Seconds the stage has been held, or 0; seconds since the last
    /// hold ended, or infinity.
    public var holding: Double = 0
    public var sinceHold: Double = .infinity
    /// The Morph's states — see `LabState.morphStates`.
    public var morphStates: [LabMorphState] = []
    /// See `LabState.pointer`.
    public var pointer: CGPoint? = nil
    /// See `LabState.spec`.
    public var spec: LabSpec = LabSpec()
    /// The live transcript's words with their age in seconds, newest
    /// last. Empty when the transcript is off or nothing has been said.
    public var transcript: [(text: String, age: Double)] = []
    public var transcribing: Bool = false

    public init(time: Double, intensity: Double, audio: Double, colors: [Color], diameter: CGFloat, darkStage: Bool,
                params: [String: Double] = [:], bands: LabAudioBands = LabAudioBands(), glyph: String? = nil,
                taps: Int = 0, sinceTap: Double = .infinity,
                hero: LabExperiment? = nil, heroPost: [LabPostEffect] = [], fill: Double = 1,
                holding: Double = 0, sinceHold: Double = .infinity, morphStates: [LabMorphState] = [], pointer: CGPoint? = nil,
                spec: LabSpec = LabSpec()) {
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
        self.fill = fill
        self.holding = holding
        self.sinceHold = sinceHold
        self.morphStates = morphStates
        self.pointer = pointer
        self.spec = spec
    }

    /// A knob's value, or its declared default when the frame was built
    /// without one (a harness, a thumbnail).
    public func p(_ id: String, _ experiment: LabExperiment) -> Double {
        params["\(experiment.id).\(id)"] ?? experiment.parameters.first { $0.id == id }?.defaultValue ?? 0
    }

    func withTranscript(_ words: [(text: String, age: Double)], on: Bool) -> LabFrame {
        var f = self
        f.transcript = words
        f.transcribing = on
        return f
    }

    /// The same frame at another size — for the pod-size preview.
    public func resized(_ d: CGFloat) -> LabFrame {
        var f = self
        f.diameter = d
        return f
    }

    /// The same frame with Libraries.dev's orb put in a given verb — how
    /// a flow drives the hero's state. No effect on any other hero.
    public func orbVerb(_ index: Double) -> LabFrame {
        var f = self
        f.params["orbKit.state"] = index
        return f
    }
}

// MARK: - Frame building, shared by the Mac stage and the iOS viewer

extension LabState {
    /// The palette, hue-drifted if asked. Drift rotates every colour's
    /// hue by the same angle, so the palette's relationships hold.
    public func colors(config: RingConfig, at time: Double) -> [Color] {
        let base = palette.colors ?? ([config.primaryColor, config.secondaryColor] + config.additionalColors)
        guard hueDrift != 0 else { return base }
        let shift = (time * hueDrift / 360).truncatingRemainder(dividingBy: 1)
        return base.map { Self.hueShifted($0, by: shift) }
    }

    public func bands(from audio: AudioSpectrumMonitor) -> LabAudioBands {
        var b = LabAudioBands()
        guard audioReactive else { return b }
        let k = audioSensitivity
        b.level = min(audio.level * k, 1.5)
        b.bass = min(audio.bass * k, 1.5)
        b.mid = min(audio.mid * k, 1.5)
        b.treble = min(audio.treble * k, 1.5)
        b.beat = min(audio.beat * k, 1.5)
        return b
    }

    /// One frame of the current experiment: the clock since `since`
    /// times `speed`, the resolved knobs, the audio, the palette.
    public func frame(at date: Date, since: Date, diameter: CGFloat, config: RingConfig, audio: AudioSpectrumMonitor) -> LabFrame {
        let elapsed = date.timeIntervalSince(since) * speed
        let bands = self.bands(from: audio)
        return LabFrame(time: elapsed,
                        intensity: intensity,
                        audio: bands.value(audioSource),
                        colors: colors(config: config, at: elapsed),
                        diameter: diameter,
                        darkStage: darkStage,
                        params: allResolvedParameters(),
                        bands: bands,
                        glyph: glyph.isEmpty ? nil : glyph,
                        taps: taps,
                        sinceTap: date.timeIntervalSince(lastTap),
                        hero: hero,
                        heroPost: post,
                        fill: fill,
                        holding: holdStart.map { date.timeIntervalSince($0) } ?? 0,
                        sinceHold: date.timeIntervalSince(holdEnd),
                        morphStates: morphStates,
                        pointer: pointer,
                        spec: spec)
            .withTranscript(audio.words.map { ($0.text, date.timeIntervalSince($0.at)) }, on: audioReactive && transcribe)
    }

    private static func hueShifted(_ color: Color, by turns: Double) -> Color {
        let rgb = PerceptualGradient.rgb(color)
        let mx = max(rgb.red, rgb.green, rgb.blue), mn = min(rgb.red, rgb.green, rgb.blue)
        let v = mx, d = mx - mn
        let s = mx == 0 ? 0 : d / mx
        var h = 0.0
        if d > 0 {
            if mx == rgb.red { h = ((rgb.green - rgb.blue) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == rgb.green { h = (rgb.blue - rgb.red) / d + 2 }
            else { h = (rgb.red - rgb.green) / d + 4 }
            h /= 6
        }
        h = (h + turns).truncatingRemainder(dividingBy: 1)
        if h < 0 { h += 1 }
        return Color(hue: h, saturation: s, brightness: v)
    }
}
