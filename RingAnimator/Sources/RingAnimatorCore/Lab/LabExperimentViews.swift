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
        let radius = 6 + frame.intensity * 40 + frame.audio * 24
        let pad = radius + 8
        ring()
            .padding(pad)
            .layerEffect(
                ShaderLibrary.bundle(.module).labBloom(
                    .float(Float(radius)),
                    .float(Float(0.6 + frame.intensity * 1.6 + frame.audio * 1.2))
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
        let amp = 1.5 + frame.intensity * 10 + frame.audio * 22
        let pad = amp + 4
        let time = Float(frame.time)
        ring()
            .padding(pad)
            .visualEffect { content, proxy in
                content.distortionEffect(
                    ShaderLibrary.bundle(.module).labRipple(
                        .float2(proxy.size),
                        .float(time),
                        .float(Float(amp))
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
        let colors = Self.nine(from: frame.colors, time: frame.time)
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
                .blur(radius: frame.diameter * 0.08)
                .scaleEffect(1.08)
                .opacity(0.55 + frame.audio * 0.4)
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
        let wobble = Float(0.1 + frame.intensity * 0.08 + frame.audio * 0.06)
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

    private static let particles: [Particle] = {
        var g = SeededGenerator(seed: 0x5EED)
        return (0..<1200).map { _ in
            let ring = Double.random(in: 0...1, using: &g)
            // Bunched toward the ring's own radius (0.72), thinning inward
            // and outward — so it reads as a halo round the ring, not a
            // uniform disc.
            let spread = (ring - 0.5) * (ring - 0.5) * 4
            let radius = 0.72 + (Double.random(in: -1...1, using: &g)) * 0.28 * spread
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
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let R = frame.diameter / 2
            let t = frame.time
            let push = 1 + frame.audio * 0.6
            let wobbleAmp = 0.03 + frame.intensity * 0.08
            context.blendMode = .plusLighter
            for p in Self.particles {
                let a = p.angle + t * p.angularSpeed
                let r = (p.baseRadius + wobbleAmp * sin(t * p.wobbleFreq + p.wobblePhase)) * push
                let x = c.x + cos(a) * r * R
                let y = c.y + sin(a) * r * R
                let s = p.size * (0.8 + frame.intensity * 0.6) * (1 + frame.audio * 0.5)
                let color = sweep.isEmpty ? Color.white : sweep[Int(p.colorT * Double(sweep.count - 1))]
                let rect = CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)
                context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.85)))
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
