import SwiftUI

// The Lab's experiments, one view each. Every one takes a `LabFrame` —
// the same time, intensity, audio and colours — so what differs between
// them is the technology, not the settings. See `LabExperiment` for what
// each is demonstrating and why.

// MARK: - Aurora (Metal · colorEffect)

struct LabAuroraView: View {
    let frame: LabFrame

    var body: some View {
        let lab = PerceptualGradient.labTriples(frame.colors)
        let time = Float(frame.time), intensity = Float(frame.intensity), audio = Float(frame.audio)
        let knobs = frame.knobs(.aurora)
        Rectangle()
            .fill(Color.white)
            .frame(width: frame.diameter, height: frame.diameter)
            .visualEffect { content, proxy in
                content.colorEffect(
                    ShaderLibrary.bundle(.module).labAurora(
                        .float2(proxy.size),
                        .float(time),
                        .float(intensity),
                        .float(audio),
                        .floatArray(knobs),
                        .floatArray(lab)
                    )
                )
            }
    }
}

// MARK: - Orb (Metal · colorEffect)

struct LabOrbView: View {
    let frame: LabFrame

    var body: some View {
        let lab = PerceptualGradient.labTriples(frame.colors)
        let time = Float(frame.time), intensity = Float(frame.intensity), audio = Float(frame.audio)
        let knobs = frame.knobs(.orb)
        Rectangle()
            .fill(Color.white)
            .frame(width: frame.diameter, height: frame.diameter)
            .visualEffect { content, proxy in
                content.colorEffect(
                    ShaderLibrary.bundle(.module).labOrb(
                        .float2(proxy.size),
                        .float(time),
                        .float(intensity),
                        .float(audio),
                        .floatArray(knobs),
                        .floatArray(lab)
                    )
                )
            }
    }
}

// MARK: - Bloom (Metal · layerEffect), over the ring

struct LabBloomView<Ring: View>: View {
    let frame: LabFrame
    @ViewBuilder let ring: () -> Ring

    var body: some View {
        // Room for the halo: the ring sits in a frame `pad` larger on each
        // side, and `maxSampleOffset` tells SwiftUI how far the shader
        // reaches so it allocates that much.
        let radius = frame.p("radius", .bloom) * (0.5 + frame.intensity) + frame.audio * 24
        let pad = radius + 8
        ring()
            .padding(pad)
            .layerEffect(
                ShaderLibrary.bundle(.module).labBloom(
                    .float(Float(radius)),
                    .float(Float(frame.p("strength", .bloom) * (0.5 + frame.intensity) + frame.audio * 1.2)),
                    .float(Float(frame.p("threshold", .bloom)))
                ),
                maxSampleOffset: CGSize(width: radius, height: radius)
            )
    }
}

// MARK: - Ripple (Metal · distortionEffect), over the ring

struct LabRippleView<Ring: View>: View {
    let frame: LabFrame
    @ViewBuilder let ring: () -> Ring

    var body: some View {
        let amp = frame.p("amp", .ripple) * (0.4 + frame.intensity * 1.2) + frame.audio * 22
        let pad = amp + 4
        let time = Float(frame.time)
        let freq = Float(frame.p("freq", .ripple)), waveSpeed = Float(frame.p("waveSpeed", .ripple))
        let hold = Float(frame.p("falloff", .ripple))
        ring()
            .padding(pad)
            .visualEffect { content, proxy in
                content.distortionEffect(
                    ShaderLibrary.bundle(.module).labRipple(
                        .float2(proxy.size),
                        .float(time),
                        .float(Float(amp)),
                        .float(freq),
                        .float(waveSpeed),
                        .float(hold)
                    ),
                    maxSampleOffset: CGSize(width: amp, height: amp)
                )
            }
    }
}

// MARK: - Mesh (SwiftUI · MeshGradient)

struct LabMeshView: View {
    let frame: LabFrame

    var body: some View {
        let points = points()
        let colors = Self.nine(from: frame.colors, time: frame.time * frame.p("drift", .mesh) / 2)
        // The mesh is drawn half again larger than the disc and clipped to
        // it, so its moving edge points never cross into the circle — the
        // first cut clipped the mesh's own frame and the disc had bites
        // out of it wherever a point had moved inward.
        let mesh = MeshGradient(width: 3, height: 3, points: points, colors: colors, smoothsColors: true)
            .frame(width: frame.diameter * 2, height: frame.diameter * 2)
        ZStack {
            // The glow: the same mesh, blurred and enlarged, underneath.
            mesh
                .frame(width: frame.diameter, height: frame.diameter)
                .clipShape(Circle())
                .blur(radius: frame.diameter * frame.p("glowBlur", .mesh))
                .scaleEffect(1.08)
                .opacity(frame.p("glow", .mesh) + frame.audio * 0.4)
            mesh
                .frame(width: frame.diameter, height: frame.diameter)
                .clipShape(Circle())
        }
    }

    /// A 3×3 mesh. The corners stay put so the disc stays filled; the
    /// edge midpoints and the centre move on incommensurate sine curves
    /// so the motion never visibly repeats.
    private func points() -> [SIMD2<Float>] {
        let t = frame.time
        let wobble = Float(min(frame.p("wobble", .mesh) * (0.6 + frame.intensity * 0.6) + frame.audio * 0.06, 0.22))
        func p(_ x: Float, _ y: Float, _ fx: Double, _ fy: Double, _ ph: Double) -> SIMD2<Float> {
            SIMD2(x + wobble * Float(sin(t * fx + ph)), y + wobble * Float(cos(t * fy + ph * 1.7)))
        }
        return [
            [0, 0],                    p(0.5, 0, 0.7, 0.9, 0.3),    [1, 0],
            p(0, 0.5, 0.8, 0.6, 1.1),  p(0.5, 0.5, 0.5, 0.65, 2.0), p(1, 0.5, 0.9, 0.7, 2.6),
            [0, 1],                    p(0.5, 1, 0.6, 0.8, 3.4),    [1, 1],
        ]
    }

    /// Nine colours from the palette, walking round it with time so the
    /// hues drift across the mesh as well as the points moving.
    private static func nine(from palette: [Color], time: Double) -> [Color] {
        let rgb = palette.map(PerceptualGradient.rgb)
        let sweep = PerceptualGradient.closedSweep(through: rgb, count: 36)
        guard !sweep.isEmpty else { return Array(repeating: .blue, count: 9) }
        let shift = Int(time * 2) % sweep.count
        return (0..<9).map { i in sweep[(i * 4 + shift) % sweep.count] }
    }
}

// MARK: - Swarm (SwiftUI · Canvas)

struct LabSwarmView: View {
    let frame: LabFrame

    /// The particles' fixed properties. Positions are computed from time
    /// each frame, so this is the only state and it never changes.
    private struct Particle {
        let baseRadius: Double   // 0…1 of the stage radius
        let angle: Double
        let angularSpeed: Double
        let wobbleFreq: Double
        let wobblePhase: Double
        let size: Double
        let colorT: Double
    }

    /// 4000 made once; a frame draws the first `count`. Deterministic, so
    /// turning Count down and back up gives the same particles.
    private static let particles: [Particle] = {
        var g = SeededGenerator(seed: 0x5EED)
        return (0..<4000).map { _ in
            let ring = Double.random(in: 0...1, using: &g)
            // Bunched toward the ring's own radius (0.72), thinning inward
            // and outward — so it reads as a halo round the ring, not a
            // uniform disc. `baseRadius` holds the *unit* offset; the
            // frame's Spread knob scales it.
            let spread = (ring - 0.5) * (ring - 0.5) * 4
            let radius = (Double.random(in: -1...1, using: &g)) * spread
            return Particle(
                baseRadius: radius,
                angle: Double.random(in: 0..<(2 * .pi), using: &g),
                angularSpeed: Double.random(in: 0.15...0.45, using: &g) * (Bool.random(using: &g) ? 1 : -1),
                wobbleFreq: Double.random(in: 0.5...1.6, using: &g),
                wobblePhase: Double.random(in: 0..<(2 * .pi), using: &g),
                size: Double.random(in: 1.2...3.2, using: &g),
                colorT: Double.random(in: 0..<1, using: &g))
        }
    }()

    var body: some View {
        let rgb = frame.colors.map(PerceptualGradient.rgb)
        let sweep = PerceptualGradient.closedSweep(through: rgb, count: 24)
        // The canvas is wider than the disc so a burst has somewhere to
        // go; `R` stays the disc's radius so the orbit sits on the ring.
        let count = min(Int(frame.p("count", .swarm)), Self.particles.count)
        let spread = frame.p("spread", .swarm)
        let orbit = frame.p("orbit", .swarm)
        let sizeMul = frame.p("size", .swarm)
        let trails = frame.p("trails", .swarm)
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let R = frame.diameter / 2
            let t = frame.time
            let push = 1 + frame.audio * 0.6
            let wobbleAmp = 0.03 + frame.intensity * 0.08
            context.blendMode = .plusLighter
            for p in Self.particles.prefix(count) {
                let color = sweep.isEmpty ? Color.white : sweep[Int(p.colorT * Double(sweep.count - 1))]
                let s = p.size * sizeMul * (0.8 + frame.intensity * 0.6) * (1 + frame.audio * 0.5)
                // Trails: the same particle a few frames back, fainter.
                // Not a history buffer — positions are a function of time,
                // so "where it was" is just an earlier `t`.
                let steps = trails > 0 ? Int(2 + trails * 10) : 0
                for k in stride(from: steps, through: 0, by: -1) {
                    let tk = t - Double(k) * 0.03
                    let a = p.angle + tk * p.angularSpeed * orbit
                    let r = (0.72 + p.baseRadius * spread + wobbleAmp * sin(tk * p.wobbleFreq + p.wobblePhase)) * push
                    let x = c.x + cos(a) * r * R
                    let y = c.y + sin(a) * r * R
                    let fade = steps == 0 ? 1.0 : 1.0 - Double(k) / Double(steps + 1)
                    let sk = s * (0.5 + 0.5 * fade)
                    let rect = CGRect(x: x - sk / 2, y: y - sk / 2, width: sk, height: sk)
                    context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.85 * fade)))
                }
            }
        }
        .frame(width: frame.diameter * 1.6, height: frame.diameter * 1.6)
    }
}

/// Deterministic randomness so the swarm is the same every launch — a
/// design being compared should not reshuffle between looks.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Refraction (Metal · layerEffect), over the ring

struct LabRefractionView<Ring: View>: View {
    let frame: LabFrame
    @ViewBuilder let ring: () -> Ring

    var body: some View {
        let lens = frame.p("lens", .refraction)
        let strength = Float(frame.p("ior", .refraction) * (0.5 + frame.intensity) + frame.audio * 0.3)
        let rim = Float(frame.p("rim", .refraction)), spec = Float(frame.p("spec", .refraction))
        let drift = frame.p("drift", .refraction)
        // The lens wanders on a slow Lissajous so the bend is seen moving
        // across the ring — a still lens over a still ring is invisible.
        let wander = CGPoint(x: sin(frame.time * 0.6) * drift * 0.25, y: cos(frame.time * 0.45) * drift * 0.25)
        let maxOffset = frame.diameter * lens * 0.5 * CGFloat(strength) * 1.6
        ring()
            .visualEffect { content, proxy in
                let radius = min(proxy.size.width, proxy.size.height) * lens * 0.5
                let center = CGPoint(x: proxy.size.width * (0.5 + wander.x), y: proxy.size.height * (0.5 + wander.y))
                return content.layerEffect(
                    ShaderLibrary.bundle(.module).labRefract(
                        .float2(center),
                        .float(Float(radius)),
                        .float(strength),
                        .float(rim),
                        .float(spec),
                        .float(Float(130.0 * Double.pi / 180))
                    ),
                    maxSampleOffset: CGSize(width: maxOffset, height: maxOffset)
                )
            }
    }
}

// MARK: - Chromatic (Metal · layerEffect), over the ring

struct LabChromaticView<Ring: View>: View {
    let frame: LabFrame
    @ViewBuilder let ring: () -> Ring

    var body: some View {
        let split = frame.p("split", .chromatic) * (0.5 + frame.intensity) + frame.audio * frame.p("beat", .chromatic)
        let radial = Float(frame.p("radial", .chromatic))
        ring()
            .padding(split + 2)
            .visualEffect { content, proxy in
                content.layerEffect(
                    ShaderLibrary.bundle(.module).labChromatic(
                        .float2(CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)),
                        .float(Float(min(proxy.size.width, proxy.size.height) / 2)),
                        .float(Float(split)),
                        .float(radial)
                    ),
                    maxSampleOffset: CGSize(width: split, height: split)
                )
            }
    }
}

extension LabFrame {
    /// The experiment's knobs as a flat float array, in declaration
    /// order — the shape a shader takes them in.
    func knobs(_ experiment: LabExperiment) -> [Float] {
        experiment.parameters.map { Float(p($0.id, experiment)) }
    }
}

// MARK: - Liquid (Metal · colorEffect)

struct LabLiquidView: View {
    let frame: LabFrame

    var body: some View {
        let lab = PerceptualGradient.labTriples(frame.colors)
        let time = Float(frame.time), intensity = Float(frame.intensity), audio = Float(frame.audio)
        let knobs = frame.knobs(.liquid)
        Rectangle()
            .fill(Color.white)
            .frame(width: frame.diameter, height: frame.diameter)
            .visualEffect { content, proxy in
                content.colorEffect(
                    ShaderLibrary.bundle(.module).labLiquid(
                        .float2(proxy.size),
                        .float(time),
                        .float(intensity),
                        .float(audio),
                        .floatArray(knobs),
                        .floatArray(lab)
                    )
                )
            }
    }
}

// MARK: - Sphere (Metal · colorEffect) — the After Effects recipe

struct LabSphereView: View {
    let frame: LabFrame

    var body: some View {
        let lab = PerceptualGradient.labTriples(frame.colors)
        let time = Float(frame.time), intensity = Float(frame.intensity), audio = Float(frame.audio)
        let knobs = frame.knobs(.sphere)
        Rectangle()
            .fill(Color.white)
            .frame(width: frame.diameter, height: frame.diameter)
            .visualEffect { content, proxy in
                content.colorEffect(
                    ShaderLibrary.bundle(.module).labSphere(
                        .float2(proxy.size),
                        .float(time),
                        .float(intensity),
                        .float(audio),
                        .floatArray(knobs),
                        .floatArray(lab)
                    )
                )
            }
    }
}

// MARK: - Rays (Metal · layerEffect), over anything

struct LabRaysView<Base: View>: View {
    let frame: LabFrame
    @ViewBuilder let ring: () -> Base

    var body: some View {
        let reach = frame.diameter * 0.5 * frame.p("length", .rays) * (0.5 + frame.intensity) + frame.audio * 40
        let strength = Float(frame.p("strength", .rays) * (0.6 + frame.intensity * 0.8) + frame.audio * 0.8)
        let decay = Float(frame.p("decay", .rays)), twist = Float(frame.p("twist", .rays))
        ring()
            .padding(reach * 0.3 + 4)
            .visualEffect { content, proxy in
                content.layerEffect(
                    ShaderLibrary.bundle(.module).labRays(
                        .float2(CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)),
                        .float(Float(reach)),
                        .float(strength),
                        .float(decay),
                        .float(twist)
                    ),
                    maxSampleOffset: CGSize(width: reach, height: reach)
                )
            }
    }
}

// MARK: - Glyph inside

/// An SF Symbol drawn over an experiment's centre — the pod's glyph
/// state, inside the effect. White with a soft shadow so it reads on
/// any palette; sized to the ring's hole.
struct LabGlyphOverlay: View {
    let frame: LabFrame

    var body: some View {
        if let glyph = frame.glyph, !glyph.isEmpty {
            Image(systemName: glyph)
                .resizable()
                .scaledToFit()
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: frame.diameter * 0.02, y: frame.diameter * 0.01)
                .frame(width: frame.diameter * 0.3, height: frame.diameter * 0.3)
                .scaleEffect(1 + frame.audio * 0.12)
        }
    }
}

// MARK: - Post stack

/// Applies the post effects in order over a base. Each is the same view
/// the experiment of that name uses, so a stacked Bloom is exactly the
/// Bloom you tuned, over whatever you tuned it for.
struct LabPostStack<Base: View>: View {
    let effects: [LabPostEffect]
    let frame: LabFrame
    @ViewBuilder let base: () -> Base

    var body: some View {
        apply(effects[...], AnyView(base()))
    }

    private func apply(_ remaining: ArraySlice<LabPostEffect>, _ view: AnyView) -> AnyView {
        guard let first = remaining.first else { return view }
        let rest = remaining.dropFirst()
        let wrapped: AnyView
        switch first {
        case .bloom:      wrapped = AnyView(LabBloomView(frame: frame) { view })
        case .rays:       wrapped = AnyView(LabRaysView(frame: frame) { view })
        case .ripple:     wrapped = AnyView(LabRippleView(frame: frame) { view })
        case .refraction: wrapped = AnyView(LabRefractionView(frame: frame) { view })
        case .chromatic:  wrapped = AnyView(LabChromaticView(frame: frame) { view })
        case .kaleido:    wrapped = AnyView(LabKaleidoView(frame: frame) { view })
        case .dots:       wrapped = AnyView(LabDotsView(frame: frame) { view })
        case .grain:      wrapped = AnyView(LabGrainView(frame: frame) { view })
        case .glitch:     wrapped = AnyView(LabGlitchView(frame: frame) { view })
        case .crt:        wrapped = AnyView(LabCRTView(frame: frame) { view })
        case .neon:       wrapped = AnyView(LabNeonView(frame: frame) { view })
        case .frost:      wrapped = AnyView(LabFrostView(frame: frame) { view })
        case .duotone:    wrapped = AnyView(LabDuotoneView(frame: frame) { view })
        case .spin:       wrapped = AnyView(LabSpinView(frame: frame) { view })
        case .tiles:      wrapped = AnyView(LabTilesView(frame: frame) { view })
        case .chrome:     wrapped = AnyView(LabChromeView(frame: frame) { view })
        case .water:      wrapped = AnyView(LabWaterView(frame: frame) { view })
        case .haze:       wrapped = AnyView(LabHazeView(frame: frame) { view })
        case .fizz:       wrapped = AnyView(LabFizzView(frame: frame) { view })
        case .glints:     wrapped = AnyView(LabGlintsView(frame: frame) { view })
        case .parallax:   wrapped = AnyView(LabParallaxView(frame: frame) { view })
        case .focus:      wrapped = AnyView(LabFocusView(frame: frame) { view })
        }
        return apply(rest, wrapped)
    }
}

// MARK: - Hero

/// What a flow draws where the ring goes: the ring, or any animation
/// lab (with the post stack) in a disc of the same size. The flows call
/// this instead of `RingView`, so "use Aurora in the chat sheet" is one
/// picker rather than a rewrite.
struct LabHeroView: View {
    let frame: LabFrame
    @ObservedObject var config: RingConfig
    /// The disc's diameter. The ring inside a pod is 34 in 62; a hero
    /// lab fills the disc, so it's drawn at the pod size.
    let diameter: CGFloat

    var body: some View {
        if let hero = frame.hero {
            LabExperimentView(experiment: hero, frame: frame.resized(diameter), config: config, post: frame.heroPost)
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
        } else {
            RingView(config: config, diameter: diameter * 0.55, overrideElapsed: frame.time)
                .frame(width: diameter, height: diameter)
        }
    }
}

// MARK: - Tunnel (Metal · colorEffect)

struct LabTunnelView: View {
    let frame: LabFrame

    var body: some View {
        let lab = PerceptualGradient.labTriples(frame.colors)
        let time = Float(frame.time), intensity = Float(frame.intensity), audio = Float(frame.audio)
        let knobs = frame.knobs(.tunnel)
        Rectangle()
            .fill(Color.white)
            .frame(width: frame.diameter, height: frame.diameter)
            .visualEffect { content, proxy in
                content.colorEffect(
                    ShaderLibrary.bundle(.module).labTunnel(
                        .float2(proxy.size), .float(time), .float(intensity), .float(audio),
                        .floatArray(knobs), .floatArray(lab)
                    )
                )
            }
    }
}

// MARK: - Constellation (SwiftUI · Canvas)

struct LabConstellationView: View {
    let frame: LabFrame

    private struct Point { let a: Double; let b: Double; let fa: Double; let fb: Double; let colorT: Double }
    private static let points: [Point] = {
        var g = SeededGenerator(seed: 0xC0FFEE)
        return (0..<300).map { _ in
            Point(a: Double.random(in: 0..<(2 * .pi), using: &g), b: Double.random(in: 0..<(2 * .pi), using: &g),
                  fa: Double.random(in: 0.15...0.5, using: &g), fb: Double.random(in: 0.15...0.5, using: &g),
                  colorT: Double.random(in: 0..<1, using: &g))
        }
    }()

    var body: some View {
        let count = min(Int(frame.p("count", .constellation)), Self.points.count)
        let link = frame.p("link", .constellation) * (1 + frame.intensity * 0.5)
        let drift = frame.p("drift", .constellation)
        let dot = frame.p("size", .constellation)
        let lw = frame.p("lineWidth", .constellation)
        let sweep = PerceptualGradient.closedSweep(through: frame.colors.map(PerceptualGradient.rgb), count: 24)
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let R = frame.diameter / 2 * 0.92
            let t = frame.time * drift
            let push = 1 + frame.audio * 0.4
            // Positions: polar, each point circling slowly while its radius
            // breathes — so they fill the disc. Cartesian Lissajous put
            // them on a square.
            let pos: [CGPoint] = Self.points.prefix(count).map { p in
                let angle = p.a + t * p.fa * 0.4
                let radius = 0.2 + 0.75 * (0.5 + 0.5 * sin(t * p.fb + p.b))
                return CGPoint(x: c.x + cos(angle) * radius * R * push, y: c.y + sin(angle) * radius * R * push)
            }
            let maxD = link * frame.diameter
            ctx.blendMode = .plusLighter
            for i in 0..<pos.count {
                for j in (i + 1)..<pos.count {
                    let d = hypot(pos[i].x - pos[j].x, pos[i].y - pos[j].y)
                    guard d < maxD else { continue }
                    let alpha = (1 - d / maxD) * 0.8
                    var path = Path()
                    path.move(to: pos[i]); path.addLine(to: pos[j])
                    let color = sweep[Int(Self.points[i].colorT * Double(sweep.count - 1))]
                    ctx.stroke(path, with: .color(color.opacity(alpha)), lineWidth: lw)
                }
            }
            for (i, p) in pos.enumerated() {
                let color = sweep[Int(Self.points[i].colorT * Double(sweep.count - 1))]
                let s = dot * (1 + frame.audio * 0.6)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)), with: .color(color))
            }
        }
        .frame(width: frame.diameter * 1.3, height: frame.diameter * 1.3)
    }
}

// MARK: - Harmonograph (SwiftUI · Canvas)

struct LabHarmonographView: View {
    let frame: LabFrame

    var body: some View {
        let fx = frame.p("fx", .harmonograph), fy = frame.p("fy", .harmonograph)
        let phase = frame.p("phase", .harmonograph)
        let decay = frame.p("decay", .harmonograph)
        let length = frame.p("length", .harmonograph) * (0.6 + frame.intensity * 0.8)
        let lw = frame.p("lineWidth", .harmonograph)
        let detune = frame.p("detune", .harmonograph)
        let sweep = PerceptualGradient.closedSweep(through: frame.colors.map(PerceptualGradient.rgb), count: 48)
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let R = frame.diameter / 2 * 0.88
            let t0 = frame.time
            // Detune drifts the frequencies slowly; audio detunes harder.
            let dfx = fx + sin(t0 * 0.13) * detune + frame.audio * 0.2
            let dfy = fy + cos(t0 * 0.11) * detune
            let steps = 900
            var last: CGPoint?
            // Draw the curve from `length` seconds ago to now, colour and
            // width fading along it so the head is bright and the tail
            // thin — a pen that is still moving.
            for i in 0..<steps {
                let u = Double(i) / Double(steps - 1)          // 0 tail … 1 head
                let s = t0 - length * (1 - u)
                let amp = exp(-decay * (1 - u) * 2)
                let x = sin(s * dfx + phase) * amp
                let y = sin(s * dfy) * amp
                let p = CGPoint(x: c.x + x * R, y: c.y + y * R)
                if let last {
                    var path = Path()
                    path.move(to: last); path.addLine(to: p)
                    let color = sweep[Int(u * Double(sweep.count - 1))]
                    ctx.stroke(path, with: .color(color.opacity(0.15 + 0.85 * u)), style: StrokeStyle(lineWidth: lw * (0.3 + 0.7 * u), lineCap: .round))
                }
                last = p
            }
        }
        .frame(width: frame.diameter, height: frame.diameter)
    }
}

// MARK: - Kaleido / Dots / Grain (Metal · layerEffect), post

struct LabKaleidoView<Base: View>: View {
    let frame: LabFrame
    @ViewBuilder let ring: () -> Base

    var body: some View {
        let segments = Float(frame.p("segments", .kaleido).rounded())
        let rotate = Float(frame.time * frame.p("rotate", .kaleido) + Double(frame.audio) * 0.5)
        let mixAmount = Float(frame.p("mix", .kaleido))
        ring()
            .visualEffect { content, proxy in
                content.layerEffect(
                    ShaderLibrary.bundle(.module).labKaleido(
                        .float2(CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)),
                        .float(segments), .float(rotate), .float(mixAmount)
                    ),
                    maxSampleOffset: CGSize(width: proxy.size.width, height: proxy.size.height)
                )
            }
    }
}

struct LabDotsView<Base: View>: View {
    let frame: LabFrame
    @ViewBuilder let ring: () -> Base

    var body: some View {
        let cell = Float(frame.p("cell", .dots))
        let lens = Float(frame.p("lens", .dots))
        let reach = CGFloat(cell) * (1 + CGFloat(lens))
        ring()
            .layerEffect(
                ShaderLibrary.bundle(.module).labDots(
                    .float(cell),
                    .float(Float(frame.p("roundness", .dots))),
                    .float(Float(frame.p("gain", .dots) * (1 + frame.audio * 0.4))),
                    .float(lens)
                ),
                maxSampleOffset: CGSize(width: reach, height: reach)
            )
    }
}

struct LabGrainView<Base: View>: View {
    let frame: LabFrame
    @ViewBuilder let ring: () -> Base

    var body: some View {
        let time = Float(frame.time)
        let amount = Float(frame.p("amount", .grain)), vignette = Float(frame.p("vignette", .grain)), desat = Float(frame.p("desat", .grain))
        ring()
            .visualEffect { content, proxy in
                content.layerEffect(
                    ShaderLibrary.bundle(.module).labGrain(
                        .float2(proxy.size), .float(time), .float(amount), .float(vignette), .float(desat)
                    ),
                    maxSampleOffset: .zero
                )
            }
    }
}
