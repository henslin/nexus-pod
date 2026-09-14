import SwiftUI

// Round three of experiments: Lightning, Cells, Warp, Burst, Symbols,
// Shapeshift, and six post effects. Same contract as the rest — a
// `LabFrame` in, a view out — split into a second file only so the first
// stays readable.

// MARK: - Cells / Shapeshift (Metal · colorEffect)

struct LabCellsView: View {
    let frame: LabFrame
    var body: some View { LabKnobShaderView(frame: frame, experiment: .cells, name: "labCells") }
}

struct LabShapeshiftView: View {
    let frame: LabFrame
    var body: some View { LabKnobShaderView(frame: frame, experiment: .shapeshift, name: "labShapeshift") }
}

/// The common shape of a knob-driven colourEffect base: size, time,
/// intensity, audio, the knobs, the palette. Looked up by name so one
/// view serves every shader with that signature.
struct LabKnobShaderView: View {
    let frame: LabFrame
    let experiment: LabExperiment
    let name: String

    var body: some View {
        let lab = PerceptualGradient.labTriples(frame.colors)
        let time = Float(frame.time), intensity = Float(frame.intensity), audio = Float(frame.audio)
        let knobs = frame.knobs(experiment)
        let fn = ShaderFunction(library: .bundle(.module), name: name)
        Rectangle()
            .fill(Color.white)
            .frame(width: frame.diameter, height: frame.diameter)
            .visualEffect { content, proxy in
                content.colorEffect(Shader(function: fn, arguments: [
                    .float2(proxy.size), .float(time), .float(intensity), .float(audio),
                    .floatArray(knobs), .floatArray(lab),
                ]))
            }
    }
}

// MARK: - Lightning (SwiftUI · Canvas)

struct LabLightningView: View {
    let frame: LabFrame

    var body: some View {
        let bolts = Int(frame.p("bolts", .lightning))
        let jitter = frame.p("jitter", .lightning)
        let rate = frame.p("rate", .lightning)
        let glow = frame.p("glow", .lightning)
        let width = frame.p("width", .lightning)
        let target = frame.p("target", .lightning)
        let primary = frame.colors.first ?? .white
        let secondary = frame.colors.count > 1 ? frame.colors[1] : primary
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let R = frame.diameter / 2 * 0.9
            // A strike lasts ~120 ms; strikes come on the beat, or on the
            // clock. Each bolt's path is seeded by the strike index so it
            // holds still for its life instead of boiling every frame.
            let strike = frame.bands.beat > 0.5 ? frame.time : floor(frame.time * rate) / rate
            let age = frame.time - strike
            let life = 0.12 + frame.intensity * 0.15
            guard age < life else { return }
            let fade = 1 - age / life
            let seed = UInt64(strike * 1000)
            for b in 0..<bolts {
                var g = SeededGenerator(seed: seed &+ UInt64(b) &* 977)
                let a0 = Double.random(in: 0..<(2 * .pi), using: &g)
                let start = CGPoint(x: c.x + cos(a0) * R, y: c.y + sin(a0) * R)
                let end: CGPoint = target < 0.5
                    ? CGPoint(x: c.x + Double.random(in: -8...8, using: &g), y: c.y + Double.random(in: -8...8, using: &g))
                    : CGPoint(x: c.x + cos(a0 + .pi + Double.random(in: -0.6...0.6, using: &g)) * R, y: c.y + sin(a0 + .pi + Double.random(in: -0.6...0.6, using: &g)) * R)
                var path = Path()
                path.move(to: start)
                let segments = 14
                for i in 1..<segments {
                    let t = Double(i) / Double(segments)
                    let px = start.x + (end.x - start.x) * t, py = start.y + (end.y - start.y) * t
                    let n = CGPoint(x: -(end.y - start.y), y: end.x - start.x)
                    let len = max(hypot(n.x, n.y), 1)
                    let off = Double.random(in: -1...1, using: &g) * jitter * R * 0.18 * sin(t * .pi)
                    path.addLine(to: CGPoint(x: px + n.x / len * off, y: py + n.y / len * off))
                }
                path.addLine(to: end)
                ctx.blendMode = .plusLighter
                ctx.stroke(path, with: .color(secondary.opacity(glow * fade)), style: StrokeStyle(lineWidth: width * 6, lineCap: .round, lineJoin: .round))
                ctx.stroke(path, with: .color(primary.opacity(fade)), style: StrokeStyle(lineWidth: width * 2.2, lineCap: .round, lineJoin: .round))
                ctx.stroke(path, with: .color(.white.opacity(fade)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: frame.diameter, height: frame.diameter)
    }
}

// MARK: - Warp (SwiftUI · Canvas)

struct LabWarpView: View {
    let frame: LabFrame

    private struct Star { let angle: Double; let phase: Double; let colorT: Double }
    private static let stars: [Star] = {
        var g = SeededGenerator(seed: 0x57A125)
        return (0..<1500).map { _ in
            Star(angle: Double.random(in: 0..<(2 * .pi), using: &g), phase: Double.random(in: 0..<1, using: &g), colorT: Double.random(in: 0..<1, using: &g))
        }
    }()

    var body: some View {
        let count = min(Int(frame.p("count", .warp)), Self.stars.count)
        let speed = frame.p("speed", .warp) * (0.6 + frame.intensity * 0.8) * (1 + frame.audio * 1.5)
        let streak = frame.p("streak", .warp) + frame.audio * 0.5
        let sizeK = frame.p("size", .warp)
        let spread = frame.p("spread", .warp)
        let sweep = PerceptualGradient.closedSweep(through: frame.colors.map(PerceptualGradient.rgb), count: 24)
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let R = frame.diameter / 2 * spread
            ctx.blendMode = .plusLighter
            for s in Self.stars.prefix(count) {
                // Depth 0…1 from the centre outward; exponential so they
                // accelerate as they approach.
                let z = (s.phase + frame.time * speed * 0.25).truncatingRemainder(dividingBy: 1)
                let r = pow(z, 2.2) * R
                let r0 = pow(max(z - 0.04 * streak, 0), 2.2) * R
                let p = CGPoint(x: c.x + cos(s.angle) * r, y: c.y + sin(s.angle) * r)
                let p0 = CGPoint(x: c.x + cos(s.angle) * r0, y: c.y + sin(s.angle) * r0)
                let color = sweep[Int(s.colorT * Double(sweep.count - 1))]
                let w = sizeK * (0.2 + z)
                var path = Path()
                path.move(to: p0); path.addLine(to: p)
                ctx.stroke(path, with: .color(color.opacity(0.3 + 0.7 * z)), style: StrokeStyle(lineWidth: w, lineCap: .round))
            }
        }
        .frame(width: frame.diameter, height: frame.diameter)
        .clipShape(Circle())
    }
}

// MARK: - Burst (SwiftUI · Canvas, on tap)

struct LabBurstView: View {
    let frame: LabFrame

    var body: some View {
        let count = Int(frame.p("count", .burst))
        let speed = frame.p("speed", .burst)
        let gravity = frame.p("gravity", .burst)
        let life = frame.p("life", .burst)
        let dot = frame.p("size", .burst)
        let spread = frame.p("spread", .burst)
        let auto = frame.p("auto", .burst) >= 0.5
        let sweep = PerceptualGradient.closedSweep(through: frame.colors.map(PerceptualGradient.rgb), count: 24)
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            // When did the last burst start? A tap, or the clock every
            // `life + 1.5` s when auto-firing.
            let period = life + 1.5
            let clockAge = frame.time.truncatingRemainder(dividingBy: period)
            let age = auto ? min(frame.sinceTap, clockAge) : frame.sinceTap
            guard age < life else { return }
            let seedBase = UInt64(((auto ? min(frame.sinceTap, clockAge) : frame.sinceTap) == frame.sinceTap ? frame.taps : Int(frame.time / period)) * 7919)
            var g = SeededGenerator(seed: seedBase &+ 1)
            ctx.blendMode = .plusLighter
            for i in 0..<count {
                let a = spread >= 1 ? Double.random(in: 0..<(2 * .pi), using: &g)
                                    : -.pi / 2 + Double.random(in: -1...1, using: &g) * spread * .pi
                let v = speed * Double.random(in: 0.35...1, using: &g)
                let x = c.x + cos(a) * v * age
                let y = c.y + sin(a) * v * age + 0.5 * gravity * age * age
                let fade = 1 - age / life
                let s = dot * (0.5 + 0.5 * fade) * Double.random(in: 0.6...1.4, using: &g)
                let color = sweep[(i * 7) % sweep.count]
                ctx.fill(Path(ellipseIn: CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)), with: .color(color.opacity(fade)))
            }
        }
        .frame(width: frame.diameter * 1.6, height: frame.diameter * 1.6)
    }
}

// MARK: - Symbols (SwiftUI · SF Symbol effects)

struct LabSymbolsView: View {
    let frame: LabFrame

    private static let glyphs = ["sparkles", "waveform", "bolt.fill", "bubble.left.and.bubble.right.fill", "house.fill", "lock.fill", "bell.fill", "person.fill"]

    var body: some View {
        let effect = Int(frame.p("effect", .symbols))
        let sizeK = frame.p("size", .symbols)
        let hold = max(frame.p("hold", .symbols), 0.2)
        let continuous = frame.p("continuous", .symbols) >= 0.5
        let index = (Int(frame.time / hold) + frame.taps) % Self.glyphs.count
        let name = frame.glyph.flatMap { $0.isEmpty ? nil : $0 } ?? Self.glyphs[index]
        let primary = frame.colors.first ?? .white
        let secondary = frame.colors.count > 1 ? frame.colors[1] : primary
        ZStack {
            Circle().fill(primary.opacity(0.12))
            Image(systemName: name)
                .font(.system(size: frame.diameter * sizeK * 0.6, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing))
                .contentTransition(.symbolEffect(.replace.downUp))
                .modifier(LabSymbolEffect(effect: effect, continuous: continuous, trigger: index))
                .shadow(color: primary.opacity(0.5), radius: 16)
        }
        .frame(width: frame.diameter, height: frame.diameter)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: index)
    }
}

/// One of the six symbol effects, continuous or fired on `trigger`.
/// Each is its own modifier call because the effect types differ.
private struct LabSymbolEffect: ViewModifier {
    let effect: Int
    let continuous: Bool
    let trigger: Int

    func body(content: Content) -> some View {
        switch effect {
        case 1:
            if continuous { content.symbolEffect(.pulse, options: .repeating) } else { content.symbolEffect(.pulse, value: trigger) }
        case 2:
            if continuous { content.symbolEffect(.variableColor.iterative, options: .repeating) } else { content.symbolEffect(.variableColor, value: trigger) }
        case 3:
            if continuous { content.symbolEffect(.wiggle, options: .repeating) } else { content.symbolEffect(.wiggle, value: trigger) }
        case 4:
            if continuous { content.symbolEffect(.breathe, options: .repeating) } else { content.symbolEffect(.breathe, value: trigger) }
        case 5:
            if continuous { content.symbolEffect(.rotate, options: .repeating) } else { content.symbolEffect(.rotate, value: trigger) }
        default:
            if continuous { content.symbolEffect(.bounce, options: .repeating) } else { content.symbolEffect(.bounce, value: trigger) }
        }
    }
}

// MARK: - Post effects (Metal · layerEffect)

struct LabGlitchView<Base: View>: View {
    let frame: LabFrame
    @ViewBuilder let ring: () -> Base

    var body: some View {
        let amount = Float(frame.p("amount", .glitch) * (0.5 + frame.intensity))
        let idle = frame.p("idle", .glitch)
        // Trigger: the beat, or a slow random gate when there is no audio.
        let gate = (sin(frame.time * 1.7) * sin(frame.time * 3.1) > 1 - idle * 0.6) ? 1.0 : 0.0
        let trigger = Float(max(frame.bands.beat, gate * 0.8))
        let blocks = Float(frame.p("blocks", .glitch))
        let time = Float(frame.time)
        let pad = CGFloat(amount) * frame.diameter * 0.25
        ring()
            .padding(.horizontal, pad)
            .visualEffect { content, proxy in
                content.layerEffect(
                    ShaderLibrary.bundle(.module).labGlitch(.float2(proxy.size), .float(time), .float(amount), .float(trigger), .float(blocks)),
                    maxSampleOffset: CGSize(width: pad, height: 0))
            }
    }
}

struct LabCRTView<Base: View>: View {
    let frame: LabFrame
    @ViewBuilder let ring: () -> Base

    var body: some View {
        let curve = Float(frame.p("curve", .crt)), lines = Float(frame.p("lines", .crt)), bleed = Float(frame.p("bleed", .crt))
        ring()
            .visualEffect { content, proxy in
                content.layerEffect(
                    ShaderLibrary.bundle(.module).labCRT(.float2(proxy.size), .float(curve), .float(lines), .float(bleed)),
                    maxSampleOffset: CGSize(width: proxy.size.width * 0.3, height: proxy.size.height * 0.3))
            }
    }
}

struct LabNeonView<Base: View>: View {
    let frame: LabFrame
    @ViewBuilder let ring: () -> Base

    var body: some View {
        let t = frame.p("thickness", .neon)
        ring()
            .layerEffect(
                ShaderLibrary.bundle(.module).labNeon(.float(Float(t)), .float(Float(frame.p("gain", .neon) * (0.6 + frame.intensity * 0.8))), .float(Float(frame.p("keep", .neon)))),
                maxSampleOffset: CGSize(width: t, height: t))
    }
}

struct LabFrostView<Base: View>: View {
    let frame: LabFrame
    @ViewBuilder let ring: () -> Base

    var body: some View {
        let amount = frame.p("amount", .frost) * (0.5 + frame.intensity)
        ring()
            .padding(amount)
            .layerEffect(
                ShaderLibrary.bundle(.module).labFrost(.float(Float(amount)), .float(Float(frame.p("scale", .frost))), .float(Float(frame.time * frame.p("melt", .frost)))),
                maxSampleOffset: CGSize(width: amount * 1.3, height: amount * 1.3))
    }
}

struct LabDuotoneView<Base: View>: View {
    let frame: LabFrame
    @ViewBuilder let ring: () -> Base

    var body: some View {
        let lab = PerceptualGradient.labTriples(frame.colors)
        ring()
            .layerEffect(
                ShaderLibrary.bundle(.module).labDuotone(.float(Float(frame.p("mix", .duotone))), .float(Float(frame.p("shift", .duotone))), .floatArray(lab)),
                maxSampleOffset: .zero)
    }
}

struct LabSpinView<Base: View>: View {
    let frame: LabFrame
    @ViewBuilder let ring: () -> Base

    var body: some View {
        let angle = Float(frame.p("angle", .spin) * (0.5 + frame.intensity) + frame.audio * 0.6)
        let radial = Float(frame.p("radial", .spin))
        ring()
            .visualEffect { content, proxy in
                content.layerEffect(
                    ShaderLibrary.bundle(.module).labSpin(.float2(CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)), .float(angle), .float(radial)),
                    maxSampleOffset: CGSize(width: proxy.size.width * 0.5, height: proxy.size.height * 0.5))
            }
    }
}

// MARK: - Lattice (SwiftUI · Canvas) — the dot-mesh sphere

/// Value noise on the CPU, for the sphere lattices. Same construction
/// as `lab_noise` in the shader, so a look tuned here reads the same
/// way a shader look does.
enum LabNoise {
    static func hash(_ x: Double, _ y: Double, _ z: Double) -> Double {
        var h = sin(x * 127.1 + y * 311.7 + z * 74.7) * 43758.5453
        h -= floor(h)
        return h
    }
    static func noise(_ x: Double, _ y: Double, _ z: Double) -> Double {
        let ix = floor(x), iy = floor(y), iz = floor(z)
        let fx = x - ix, fy = y - iy, fz = z - iz
        let ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy), uz = fz * fz * (3 - 2 * fz)
        func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
        let c00 = lerp(hash(ix, iy, iz), hash(ix + 1, iy, iz), ux)
        let c10 = lerp(hash(ix, iy + 1, iz), hash(ix + 1, iy + 1, iz), ux)
        let c01 = lerp(hash(ix, iy, iz + 1), hash(ix + 1, iy, iz + 1), ux)
        let c11 = lerp(hash(ix, iy + 1, iz + 1), hash(ix + 1, iy + 1, iz + 1), ux)
        return lerp(lerp(c00, c10, uy), lerp(c01, c11, uy), uz)
    }
    static func fbm(_ x: Double, _ y: Double, _ z: Double, octaves: Int = 3) -> Double {
        var v = 0.0, a = 0.5, px = x, py = y, pz = z
        for _ in 0..<octaves {
            v += a * noise(px, py, pz)
            px *= 2.03; py *= 2.03; pz *= 2.03
            a *= 0.5
        }
        return v
    }
}

struct LabLatticeView: View {
    let frame: LabFrame

    var body: some View {
        let cols = Int(frame.p("cols", .lattice)), rows = Int(frame.p("rows", .lattice))
        let amp = frame.p("amp", .lattice) * (0.6 + frame.intensity * 0.8) + frame.audio * 0.25
        let scale = frame.p("scale", .lattice)
        let flow = frame.p("flow", .lattice)
        let dotSize = frame.p("dot", .lattice)
        let tilt = frame.p("tilt", .lattice)
        let spin = frame.p("spin", .lattice)
        let back = frame.p("back", .lattice)
        let sweep = PerceptualGradient.closedSweep(through: frame.colors.map(PerceptualGradient.rgb), count: 32)
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let R = frame.diameter / 2 * 0.72
            let t = frame.time
            let ry = t * spin, rx = tilt
            let cy = cos(ry), sy = sin(ry), cx = cos(rx), sx = sin(rx)
            struct Dot { let p: CGPoint; let z: Double; let d: Double; let v: Double }
            var dots: [Dot] = []
            dots.reserveCapacity(cols * rows)
            for j in 0..<rows {
                let v = (Double(j) + 0.5) / Double(rows)          // 0…1 pole to pole
                let phi = v * .pi
                for i in 0..<cols {
                    let theta = Double(i) / Double(cols) * 2 * .pi
                    // Unit sphere point, displaced along its normal by noise.
                    var x = sin(phi) * cos(theta), y = cos(phi), z = sin(phi) * sin(theta)
                    let n = LabNoise.fbm(x * scale + t * flow * 0.3, y * scale + t * flow * 0.2, z * scale - t * flow * 0.25)
                    let disp = 1 + (n - 0.5) * 2 * amp
                    x *= disp; y *= disp; z *= disp
                    // Rotate: about Y (spin), then X (tilt).
                    let x1 = x * cy + z * sy, z1 = -x * sy + z * cy
                    let y2 = y * cx - z1 * sx, z2 = y * sx + z1 * cx
                    dots.append(Dot(p: CGPoint(x: c.x + x1 * R, y: c.y - y2 * R), z: z2, d: disp, v: v))
                }
            }
            dots.sort { $0.z < $1.z }   // back to front
            ctx.blendMode = .plusLighter
            for d in dots {
                let front = d.z > 0
                if !front && back <= 0 { continue }
                // Colour by latitude and displacement; size by depth so
                // the near side reads as near.
                let tcol = (d.v * 0.7 + (d.d - 1) * 0.8 + t * 0.02).truncatingRemainder(dividingBy: 1)
                let color = sweep[Int(abs(tcol) * Double(sweep.count - 1))]
                let s = dotSize * (0.55 + 0.45 * (d.z + 1) / 2) * (0.8 + 0.4 * d.d)
                let alpha = front ? 0.95 : back * 0.5
                ctx.fill(Path(ellipseIn: CGRect(x: d.p.x - s / 2, y: d.p.y - s / 2, width: s, height: s)), with: .color(color.opacity(alpha)))
            }
        }
        .frame(width: frame.diameter, height: frame.diameter)
    }
}

// MARK: - Stipple (SwiftUI · Canvas) — the particle sphere

struct LabStippleView: View {
    let frame: LabFrame

    private struct P { let x: Double; let y: Double; let z: Double; let s: Double; let k: Double }
    private static let points: [P] = {
        var g = SeededGenerator(seed: 0x5719)
        return (0..<6000).map { _ in
            // Uniform on the sphere.
            let u = Double.random(in: -1...1, using: &g), a = Double.random(in: 0..<(2 * .pi), using: &g)
            let r = sqrt(1 - u * u)
            return P(x: r * cos(a), y: u, z: r * sin(a), s: Double.random(in: 0.5...1.6, using: &g), k: Double.random(in: 0..<1, using: &g))
        }
    }()

    var body: some View {
        let count = min(Int(frame.p("count", .stipple)), Self.points.count)
        let rim = frame.p("rim", .stipple)
        let dot = frame.p("dot", .stipple)
        let spin = frame.p("spin", .stipple)
        let jitter = frame.p("jitter", .stipple) + frame.audio * 0.1
        let tint = frame.p("tint", .stipple)
        let sweep = PerceptualGradient.closedSweep(through: frame.colors.map(PerceptualGradient.rgb), count: 16)
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let R = frame.diameter / 2 * 0.8 * (1 + frame.audio * 0.08)
            let t = frame.time
            let cy = cos(t * spin), sy = sin(t * spin)
            ctx.blendMode = .plusLighter
            for p in Self.points.prefix(count) {
                let x1 = p.x * cy + p.z * sy, z1 = -p.x * sy + p.z * cy
                // Breathing: each point drifts a little off the surface.
                let breathe = 1 + jitter * sin(t * 1.3 + p.k * 6.28) * 0.5
                let px = c.x + x1 * R * breathe, py = c.y - p.y * R * breathe
                // Rim weighting: the reference is dense and bright at the
                // silhouette, sparse in the middle — |z| small means near
                // the edge in projection.
                let edge = 1 - abs(z1)
                let w = 0.15 + rim * pow(edge, 3)
                let base = tint > 0 ? sweep[Int(p.k * Double(sweep.count - 1))] : Color.white
                let color = tint > 0 ? base.opacity(1) : base
                let s = dot * p.s * (0.7 + 0.5 * edge)
                ctx.fill(Path(ellipseIn: CGRect(x: px - s / 2, y: py - s / 2, width: s, height: s)), with: .color(color.opacity(min(w, 1) * (z1 > 0 ? 1 : 0.35))))
            }
        }
        .frame(width: frame.diameter, height: frame.diameter)
    }
}

// MARK: - Tiles (Metal · layerEffect), post

struct LabTilesView<Base: View>: View {
    let frame: LabFrame
    @ViewBuilder let ring: () -> Base

    var body: some View {
        let cell = frame.p("cell", .tiles)
        let bulge = frame.p("bulge", .tiles) * (0.5 + frame.intensity)
        ring()
            .padding(cell)
            .visualEffect { content, proxy in
                content.layerEffect(
                    ShaderLibrary.bundle(.module).labTiles(
                        .float2(proxy.size), .float(Float(cell)), .float(Float(bulge)),
                        .float(Float(frame.p("frost", .tiles))), .float(Float(frame.p("grout", .tiles))),
                        .float(Float(frame.p("coverage", .tiles)))),
                    maxSampleOffset: CGSize(width: cell, height: cell))
            }
    }
}
