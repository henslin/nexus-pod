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
        let frost = Float(frame.p("frost", .tiles)), grout = Float(frame.p("grout", .tiles))
        let coverage = Float(frame.p("coverage", .tiles)), orientation = Float(frame.p("orientation", .tiles))
        ring()
            .padding(cell)
            .visualEffect { content, proxy in
                content.layerEffect(
                    ShaderLibrary.bundle(.module).labTiles(
                        .float2(proxy.size), .float(Float(cell)), .float(Float(bulge)),
                        .float(frost), .float(grout), .float(coverage), .float(orientation)),
                    maxSampleOffset: CGSize(width: cell, height: cell))
            }
    }
}

// MARK: - Bubble / Slices (Metal · colorEffect)

struct LabBubbleView: View {
    let frame: LabFrame
    var body: some View { LabKnobShaderView(frame: frame, experiment: .bubble, name: "labBubble") }
}

struct LabSlicesView: View {
    let frame: LabFrame
    var body: some View { LabKnobShaderView(frame: frame, experiment: .slices, name: "labSlices") }
}

// MARK: - Stack (SwiftUI · Canvas) — planes receding in depth

struct LabStackView: View {
    let frame: LabFrame

    var body: some View {
        let count = Int(frame.p("count", .stack))
        let depth = frame.p("depth", .stack)
        let opacity = frame.p("opacity", .stack)
        let shapeK = frame.p("shape", .stack)
        let sway = frame.p("sway", .stack) * (0.5 + frame.intensity) + frame.audio * 0.3
        let perspective = frame.p("perspective", .stack)
        let sweep = PerceptualGradient.closedSweep(through: frame.colors.map(PerceptualGradient.rgb), count: max(count, 2))
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let base = frame.diameter * 0.62
            ctx.blendMode = .plusLighter
            // Back to front. Each plane is smaller and shifted by depth, so
            // they read as a corridor; sway rolls the whole stack.
            for i in stride(from: count - 1, through: 0, by: -1) {
                let z = Double(i) / Double(max(count - 1, 1))          // 0 front … 1 back
                let scale = 1 - z * depth * 0.6
                let shift = CGPoint(x: sin(frame.time * 0.7) * sway * 60 * z + z * depth * perspective * 80,
                                    y: cos(frame.time * 0.5) * sway * 40 * z)
                let s = base * scale
                let rect = CGRect(x: c.x - s / 2 + shift.x, y: c.y - s / 2 + shift.y, width: s, height: s)
                let color = sweep[(i * sweep.count / max(count, 1)) % sweep.count]
                let path = shapeK < 0.5
                    ? Path(roundedRect: rect, cornerRadius: s * 0.08)
                    : Path(ellipseIn: rect)
                ctx.fill(path, with: .color(color.opacity(opacity)))
                ctx.stroke(path, with: .color(color.opacity(min(1, opacity * 2.2))), lineWidth: 1)
            }
        }
        .frame(width: frame.diameter * 1.5, height: frame.diameter * 1.5)
    }
}

// MARK: - Cascade (SwiftUI · Canvas) — Retoka's overlapping shapes

struct LabCascadeView: View {
    let frame: LabFrame

    var body: some View {
        let count = Int(frame.p("count", .cascade))
        let step = frame.p("step", .cascade)
        let opacity = frame.p("opacity", .cascade)
        let swing = frame.p("swing", .cascade) * (0.5 + frame.intensity) + frame.audio * 0.5
        let corner = frame.p("corner", .cascade)
        let multiply = frame.p("multiply", .cascade) >= 0.5
        let sweep = PerceptualGradient.closedSweep(through: frame.colors.map(PerceptualGradient.rgb), count: max(count, 2))
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let s = frame.diameter * 0.62
            ctx.blendMode = multiply ? .multiply : .plusLighter
            // Overlapping rounded shapes offset down a slow arc — the
            // reference's cascade — each in the next palette colour.
            // Step is in shape heights; the whole cascade is centred, and
            // swings sideways along a gentle arc that breathes with time.
            let h = s * 0.86
            let total = step * h * Double(max(count - 1, 1))
            for i in 0..<count {
                let u = Double(i) / Double(max(count - 1, 1))
                let dy = -total / 2 + step * h * Double(i)
                let dx = sin((u - 0.5) * .pi) * swing * s * 0.5 + sin(frame.time * 0.6 + u * 3) * swing * 8
                let rect = CGRect(x: c.x - s / 2 + dx, y: c.y - h / 2 + dy, width: s, height: h)
                let color = sweep[(i * sweep.count / max(count, 1)) % sweep.count]
                let path = Path(roundedRect: rect, cornerRadius: s * corner)
                ctx.fill(path, with: .color(color.opacity(opacity)))
            }
        }
        .frame(width: frame.diameter * 1.5, height: frame.diameter * 1.5)
    }
}

// MARK: - Prism (SwiftUI · Canvas) — the dispersion cube

struct LabPrismView: View {
    let frame: LabFrame

    var body: some View {
        let dispersion = frame.p("dispersion", .prism) * (0.5 + frame.intensity)
        let spin = frame.p("spin", .prism)
        let tilt = frame.p("tilt", .prism)
        let faceAlpha = frame.p("faces", .prism)
        let edgeWidth = frame.p("edge", .prism)
        let glow = frame.p("glow", .prism)
        let primary = frame.colors.first ?? .white
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let R = frame.diameter * 0.26
            let t = frame.time
            // A unit cube, rotated about Y and X, projected with a little
            // perspective.
            let ry = t * spin, rx = tilt + sin(t * 0.4) * 0.15
            let cy = cos(ry), sy = sin(ry), cx = cos(rx), sx = sin(rx)
            func project(_ v: SIMD3<Double>) -> (CGPoint, Double) {
                let x1 = v.x * cy + v.z * sy, z1 = -v.x * sy + v.z * cy
                let y2 = v.y * cx - z1 * sx, z2 = v.y * sx + z1 * cx
                let persp = 1 / (1 + z2 * 0.18)
                return (CGPoint(x: c.x + x1 * R * persp, y: c.y - y2 * R * persp), z2)
            }
            let verts: [SIMD3<Double>] = [
                [-1, -1, -1], [1, -1, -1], [1, 1, -1], [-1, 1, -1],
                [-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1],
            ]
            let p = verts.map(project)
            let faces = [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [2, 3, 7, 6], [0, 3, 7, 4], [1, 2, 6, 5]]
            // Faces: faint glass, back faces first.
            let sorted = faces.sorted { a, b in
                a.map { p[$0].1 }.reduce(0, +) < b.map { p[$0].1 }.reduce(0, +)
            }
            for f in sorted {
                var path = Path()
                path.move(to: p[f[0]].0)
                for k in f.dropFirst() { path.addLine(to: p[k].0) }
                path.closeSubpath()
                let depth = f.map { p[$0].1 }.reduce(0, +) / 4
                ctx.fill(path, with: .color(primary.opacity(faceAlpha * (0.5 + 0.5 * (depth + 1) / 2))))
            }
            // Edges: three strokes, red / green / blue, each offset along
            // the edge's normal by a different amount — dispersion. Then a
            // white core.
            let edges = [(0,1),(1,2),(2,3),(3,0),(4,5),(5,6),(6,7),(7,4),(0,4),(1,5),(2,6),(3,7)]
            ctx.blendMode = .plusLighter
            for (a, b) in edges {
                let pa = p[a].0, pb = p[b].0
                let dx = pb.x - pa.x, dy = pb.y - pa.y
                let len = max(hypot(dx, dy), 1)
                let n = CGPoint(x: -dy / len, y: dx / len)
                let near = (p[a].1 + p[b].1) / 2
                let bright = 0.45 + 0.55 * (near + 1) / 2
                let channels: [(Color, Double)] = [(.red, -1), (.green, 0), (.blue, 1)]
                for (color, k) in channels {
                    var path = Path()
                    let o = CGPoint(x: n.x * k * dispersion * 4, y: n.y * k * dispersion * 4)
                    path.move(to: CGPoint(x: pa.x + o.x, y: pa.y + o.y))
                    path.addLine(to: CGPoint(x: pb.x + o.x, y: pb.y + o.y))
                    ctx.stroke(path, with: .color(color.opacity(bright * 0.8)), style: StrokeStyle(lineWidth: edgeWidth * 2.5, lineCap: .round))
                    ctx.stroke(path, with: .color(color.opacity(bright * glow * 0.4)), style: StrokeStyle(lineWidth: edgeWidth * 8, lineCap: .round))
                }
                var core = Path()
                core.move(to: pa); core.addLine(to: pb)
                ctx.stroke(core, with: .color(.white.opacity(bright)), style: StrokeStyle(lineWidth: edgeWidth, lineCap: .round))
            }
        }
        .frame(width: frame.diameter, height: frame.diameter)
    }
}

// MARK: - Chrome (Metal · layerEffect), post

struct LabChromeView<Base: View>: View {
    let frame: LabFrame
    @ViewBuilder let ring: () -> Base

    var body: some View {
        let bevel = frame.p("bevel", .chrome)
        let lab = PerceptualGradient.labTriples(frame.colors)
        ring()
            .layerEffect(
                ShaderLibrary.bundle(.module).labChrome(
                    .float(Float(bevel)), .float(Float(frame.p("iridescence", .chrome))),
                    .float(Float(frame.p("shine", .chrome) * (0.7 + frame.intensity * 0.6))),
                    .float(Float(frame.p("keep", .chrome))), .float(Float(frame.time)),
                    .floatArray(lab)),
                maxSampleOffset: CGSize(width: bevel * 2, height: bevel * 2))
    }
}

// MARK: - Holo / Lenticular / Moiré (Metal · colorEffect)

struct LabHoloView: View {
    let frame: LabFrame
    var body: some View { LabKnobShaderView(frame: frame, experiment: .holo, name: "labHolo") }
}

struct LabLenticularView: View {
    let frame: LabFrame
    var body: some View { LabKnobShaderView(frame: frame, experiment: .lenticular, name: "labLenticular") }
}

struct LabMoireView: View {
    let frame: LabFrame
    var body: some View { LabKnobShaderView(frame: frame, experiment: .moire, name: "labMoire") }
}

// MARK: - Orrery (SwiftUI · Canvas) — rings in 3D, with dispersion edges

struct LabOrreryView: View {
    let frame: LabFrame

    var body: some View {
        let count = Int(frame.p("rings", .orrery))
        let spin = frame.p("spin", .orrery)
        let dispersion = frame.p("dispersion", .orrery) * (0.5 + frame.intensity)
        let width = frame.p("width", .orrery)
        let spacing = frame.p("spacing", .orrery)
        let glow = frame.p("glow", .orrery)
        let sweep = PerceptualGradient.closedSweep(through: frame.colors.map(PerceptualGradient.rgb), count: max(count, 2))
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let R0 = frame.diameter / 2 * 0.78
            let t = frame.time
            // Each ring is a circle in 3D on its own tilted axis, turning
            // at its own rate; projected as a polyline so the near half
            // can be drawn over the far half.
            struct Seg { let a: CGPoint; let b: CGPoint; let z: Double; let ring: Int }
            var segs: [Seg] = []
            for i in 0..<count {
                let R = R0 * (1 - spacing * Double(i) / Double(max(count, 1)))
                let tiltX = 0.5 + Double(i) * 0.7, tiltY = Double(i) * 1.1
                let rate = spin * (0.6 + Double(i) * 0.35) * (i % 2 == 0 ? 1 : -1)
                let steps = 72
                var prev: (CGPoint, Double)?
                for k in 0...steps {
                    let a = Double(k) / Double(steps) * 2 * .pi
                    var x = cos(a) * R, y = sin(a) * R, z = 0.0
                    // Rotate: about X by tiltX, about Y by tiltY + spin.
                    let cx = cos(tiltX), sx = sin(tiltX)
                    let y1 = y * cx - z * sx, z1 = y * sx + z * cx
                    let ay = tiltY + t * rate
                    let cy = cos(ay), sy = sin(ay)
                    let x2 = x * cy + z1 * sy, z2 = -x * sy + z1 * cy
                    x = x2; y = y1; z = z2
                    let p = CGPoint(x: c.x + x, y: c.y - y)
                    if let prev { segs.append(Seg(a: prev.0, b: p, z: (prev.1 + z) / 2, ring: i)) }
                    prev = (p, z)
                }
            }
            segs.sort { $0.z < $1.z }
            ctx.blendMode = .plusLighter
            for s in segs {
                let depth = (s.z / R0 + 1) / 2                       // 0 far … 1 near
                let bright = 0.25 + 0.75 * depth
                let color = sweep[(s.ring * sweep.count / max(count, 1)) % sweep.count]
                let dx = s.b.x - s.a.x, dy = s.b.y - s.a.y
                let len = max(hypot(dx, dy), 0.001)
                let n = CGPoint(x: -dy / len, y: dx / len)
                // Dispersion: R and B offset along the normal, G on the line.
                for (ch, k) in [(Color.red, -1.0), (Color.green, 0.0), (Color.blue, 1.0)] {
                    var path = Path()
                    path.move(to: CGPoint(x: s.a.x + n.x * k * dispersion * 3, y: s.a.y + n.y * k * dispersion * 3))
                    path.addLine(to: CGPoint(x: s.b.x + n.x * k * dispersion * 3, y: s.b.y + n.y * k * dispersion * 3))
                    ctx.stroke(path, with: .color(ch.opacity(bright * 0.6)), style: StrokeStyle(lineWidth: width * 1.6, lineCap: .round))
                }
                var core = Path()
                core.move(to: s.a); core.addLine(to: s.b)
                ctx.stroke(core, with: .color(color.opacity(bright * glow * 0.6)), style: StrokeStyle(lineWidth: width * 5, lineCap: .round))
                ctx.stroke(core, with: .color(.white.opacity(bright)), style: StrokeStyle(lineWidth: width * 0.7, lineCap: .round))
            }
        }
        .frame(width: frame.diameter, height: frame.diameter)
    }
}

// MARK: - Bokeh (SwiftUI · Canvas) — out-of-focus lights

struct LabBokehView: View {
    let frame: LabFrame

    private struct Light { let x: Double; let y: Double; let z: Double; let fx: Double; let fy: Double; let colorT: Double; let seed: Double }
    private static let lights: [Light] = {
        var g = SeededGenerator(seed: 0xB0CE)
        return (0..<120).map { _ in
            Light(x: Double.random(in: -1...1, using: &g), y: Double.random(in: -1...1, using: &g),
                  z: Double.random(in: 0...1, using: &g),
                  fx: Double.random(in: 0.1...0.4, using: &g), fy: Double.random(in: 0.1...0.4, using: &g),
                  colorT: Double.random(in: 0..<1, using: &g), seed: Double.random(in: 0..<6.28, using: &g))
        }
    }()

    var body: some View {
        let count = min(Int(frame.p("count", .bokeh)), Self.lights.count)
        let sizeK = frame.p("size", .bokeh)
        let edge = frame.p("edge", .bokeh)
        let drift = frame.p("drift", .bokeh)
        let sides = Int(frame.p("sides", .bokeh))
        let focus = frame.p("focus", .bokeh)
        let sweep = PerceptualGradient.closedSweep(through: frame.colors.map(PerceptualGradient.rgb), count: 24)
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let R = frame.diameter / 2
            let t = frame.time * drift
            ctx.blendMode = .plusLighter
            // Far lights are big and soft, near ones small and sharp — the
            // way a lens renders points at different depths. Focus slides
            // which depth is sharp.
            for l in Self.lights.prefix(count).sorted(by: { $0.z < $1.z }) {
                let x = c.x + (l.x + sin(t * l.fx + l.seed) * 0.25) * R * 0.85
                let y = c.y + (l.y + cos(t * l.fy + l.seed) * 0.25) * R * 0.85
                let blur = abs(l.z - focus)                          // 0 sharp … 1 very soft
                let d = sizeK * R * (0.06 + blur * 0.35) * (1 + frame.audio * 0.3)
                let color = sweep[Int(l.colorT * Double(sweep.count - 1))]
                let alpha = (0.9 - blur * 0.6) * (0.5 + frame.intensity * 0.5)
                let rect = CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)
                let path: Path = sides < 3 ? Path(ellipseIn: rect) : Self.polygon(in: rect, sides: sides, rotation: l.seed)
                // A soft body that brightens toward the rim, then falls off
                // — the profile of a real bokeh disc. Sharp (in-focus)
                // lights get a hotter core; soft ones are all rim.
                let core = alpha * (0.15 + 0.6 * (1 - blur))
                let rim = alpha * edge * 0.7
                let shading = GraphicsContext.Shading.radialGradient(
                    Gradient(stops: [
                        .init(color: color.opacity(core), location: 0),
                        .init(color: color.opacity(alpha * 0.3), location: 0.55),
                        .init(color: color.opacity(rim), location: 0.88),
                        .init(color: color.opacity(0), location: 1),
                    ]),
                    center: CGPoint(x: x, y: y), startRadius: 0, endRadius: d / 2)
                ctx.fill(path, with: shading)
            }
        }
        .frame(width: frame.diameter, height: frame.diameter)
        .clipShape(Circle())
    }

    private static func polygon(in rect: CGRect, sides: Int, rotation: Double) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY), r = rect.width / 2
        for i in 0..<sides {
            let a = rotation + Double(i) / Double(sides) * 2 * .pi
            let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Frost Orb / Globe / Silk / Liquid Ring (Metal · colorEffect)

struct LabFrostOrbView: View {
    let frame: LabFrame
    var body: some View { LabKnobShaderView(frame: frame, experiment: .frostOrb, name: "labFrostOrb") }
}

struct LabGlobeView: View {
    let frame: LabFrame
    var body: some View { LabKnobShaderView(frame: frame, experiment: .globe, name: "labGlobe") }
}

struct LabSilkView: View {
    let frame: LabFrame
    var body: some View { LabKnobShaderView(frame: frame, experiment: .silk, name: "labSilk") }
}

struct LabLiquidRingView: View {
    let frame: LabFrame
    var body: some View { LabKnobShaderView(frame: frame, experiment: .liquidRing, name: "labLiquidRing") }
}

// MARK: - Tide (Metal · colorEffect) — water in a sphere

struct LabTideView: View {
    let frame: LabFrame
    var body: some View { LabKnobShaderView(frame: frame, experiment: .tide, name: "labTide") }
}

// MARK: - Round five bases (Metal · colorEffect)

struct LabDropletView: View { let frame: LabFrame; var body: some View { LabKnobShaderView(frame: frame, experiment: .droplet, name: "labDroplet") } }
struct LabPourView: View { let frame: LabFrame; var body: some View { LabKnobShaderView(frame: frame, experiment: .pour, name: "labPour") } }
struct LabPoolView: View { let frame: LabFrame; var body: some View { LabKnobShaderView(frame: frame, experiment: .pool, name: "labPool") } }
struct LabCausticsView: View { let frame: LabFrame; var body: some View { LabKnobShaderView(frame: frame, experiment: .caustics, name: "labCaustics") } }
struct LabLavaView: View { let frame: LabFrame; var body: some View { LabKnobShaderView(frame: frame, experiment: .lava, name: "labLava") } }
struct LabJellyView: View { let frame: LabFrame; var body: some View { LabKnobShaderView(frame: frame, experiment: .jelly, name: "labJelly") } }
struct LabSlickView: View { let frame: LabFrame; var body: some View { LabKnobShaderView(frame: frame, experiment: .slick, name: "labSlick") } }
struct LabDeepView: View { let frame: LabFrame; var body: some View { LabKnobShaderView(frame: frame, experiment: .deep, name: "labDeep") } }
struct LabNebulaView: View { let frame: LabFrame; var body: some View { LabKnobShaderView(frame: frame, experiment: .nebula, name: "labNebula") } }

// MARK: - Round five post effects (Metal · layerEffect)

struct LabWaterView<Base: View>: View {
    let frame: LabFrame
    @ViewBuilder let ring: () -> Base
    var body: some View {
        let amount = frame.p("amount", .water) * (0.5 + frame.intensity) + frame.audio * 8
        let time = Float(frame.time * frame.p("speed", .water))
        let scale = Float(frame.p("scale", .water)), caustic = Float(frame.p("caustic", .water))
        ring()
            .padding(amount)
            .visualEffect { content, proxy in
                content.layerEffect(
                    ShaderLibrary.bundle(.module).labWater(.float2(proxy.size), .float(time), .float(Float(amount)),
                                                            .float(scale), .float(caustic)),
                    maxSampleOffset: CGSize(width: amount * 1.5, height: amount * 1.5))
            }
    }
}

struct LabHazeView<Base: View>: View {
    let frame: LabFrame
    @ViewBuilder let ring: () -> Base
    var body: some View {
        let lab = PerceptualGradient.labTriples(frame.colors)
        let time = Float(frame.time)
        // Read the knobs here, not in the effect closure: it's Sendable,
        // and the frame is main-actor.
        let amount = Float(frame.p("amount", .haze) * (0.6 + frame.intensity * 0.6))
        let scale = Float(frame.p("scale", .haze)), breathe = Float(frame.p("breathe", .haze))
        ring()
            .visualEffect { content, proxy in
                content.layerEffect(
                    ShaderLibrary.bundle(.module).labHaze(.float2(proxy.size), .float(time),
                                                           .float(amount), .float(scale), .float(breathe),
                                                           .floatArray(lab)),
                    maxSampleOffset: .zero)
            }
    }
}

struct LabFizzView<Base: View>: View {
    let frame: LabFrame
    @ViewBuilder let ring: () -> Base
    var body: some View {
        let time = Float(frame.time)
        let count = Float(frame.p("count", .fizz) * (0.6 + frame.intensity * 0.8) + frame.audio * 10)
        let speed = Float(frame.p("speed", .fizz)), size = Float(frame.p("size", .fizz))
        ring()
            .visualEffect { content, proxy in
                content.layerEffect(
                    ShaderLibrary.bundle(.module).labFizz(.float2(proxy.size), .float(time),
                                                           .float(count), .float(speed), .float(size)),
                    maxSampleOffset: .zero)
            }
    }
}

struct LabGlintsView<Base: View>: View {
    let frame: LabFrame
    @ViewBuilder let ring: () -> Base
    var body: some View {
        let len = frame.p("length", .glints) * (0.5 + frame.intensity) + frame.audio * 30
        ring()
            .padding(len)
            .layerEffect(
                ShaderLibrary.bundle(.module).labGlints(.float(Float(frame.p("threshold", .glints))), .float(Float(len)),
                                                         .float(Float(frame.p("strength", .glints))), .float(Float(frame.time * frame.p("rotate", .glints)))),
                maxSampleOffset: CGSize(width: len, height: len))
    }
}

struct LabParallaxView<Base: View>: View {
    let frame: LabFrame
    @ViewBuilder let ring: () -> Base
    var body: some View {
        let off = frame.p("offset", .parallax)
        let angle = frame.p("angle", .parallax)
        let offset = CGPoint(x: cos(angle) * off, y: sin(angle) * off)
        let soften = frame.p("soften", .parallax)
        ring()
            .padding(off + soften)
            .layerEffect(
                ShaderLibrary.bundle(.module).labParallax(.float2(offset), .float(Float(frame.p("shadow", .parallax))),
                                                           .float(Float(frame.p("light", .parallax))), .float(Float(soften))),
                maxSampleOffset: CGSize(width: off + soften, height: off + soften))
    }
}

// MARK: - Focus (Metal · layerEffect), post — depth of field

struct LabFocusView<Base: View>: View {
    let frame: LabFrame
    @ViewBuilder let ring: () -> Base
    var body: some View {
        let radius = frame.p("radius", .focus) * (0.5 + frame.intensity) + frame.audio * 10
        let drift = frame.p("drift", .focus)
        let fx = Float(frame.p("x", .focus) + sin(frame.time * 0.5) * drift * 0.3)
        let fy = Float(frame.p("y", .focus) + cos(frame.time * 0.37) * drift * 0.3)
        let band = Float(frame.p("band", .focus)), falloff = Float(frame.p("falloff", .focus)), bokeh = Float(frame.p("bokeh", .focus))
        ring()
            .padding(radius)
            .visualEffect { content, proxy in
                content.layerEffect(
                    ShaderLibrary.bundle(.module).labFocus(.float2(proxy.size), .float2(CGPoint(x: CGFloat(fx), y: CGFloat(fy))),
                                                            .float(Float(radius)), .float(band), .float(falloff), .float(bokeh)),
                    maxSampleOffset: CGSize(width: radius, height: radius))
            }
    }
}

// MARK: - Thinking Orbs (SwiftUI · Canvas) — the libraries.dev reference

/// A cloud of dots with nine states of motion — Working, Searching,
/// Solving, Listening, Connecting, Weaving, Composing, Breathing,
/// Shaping — the "Thinking orbs" library Chris pointed at (2026-09-15),
/// done natively. Every position is a function of time and the dot's
/// seed, so there is no simulation and the state switches are clean.
struct LabThinkingOrbsView: View {
    let frame: LabFrame

    private struct Dot { let a: Double; let b: Double; let r: Double; let k: Double; let s: Double }
    private static let dots: [Dot] = {
        var g = SeededGenerator(seed: 0x7411)
        return (0..<200).map { _ in
            Dot(a: Double.random(in: 0..<(2 * .pi), using: &g), b: Double.random(in: 0..<(2 * .pi), using: &g),
                r: Double.random(in: 0.2...1, using: &g), k: Double.random(in: 0..<1, using: &g), s: Double.random(in: 0.6...1.4, using: &g))
        }
    }()

    var body: some View {
        let state = Int(frame.p("state", .thinkingOrbs))
        let count = min(Int(frame.p("count", .thinkingOrbs)), Self.dots.count)
        let dotSize = frame.p("dotSize", .thinkingOrbs)
        let orbits = frame.p("orbits", .thinkingOrbs)
        let particles = Int(frame.p("particles", .thinkingOrbs))
        let colourMode = Int(frame.p("colour", .thinkingOrbs))
        let sweep = PerceptualGradient.closedSweep(through: frame.colors.map(PerceptualGradient.rgb), count: 24)
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let R = frame.diameter / 2 * 0.82
            let t = frame.time * (0.7 + frame.intensity * 0.6)
            let audio = frame.audio
            let first = frame.colors.first ?? .white
            func color(_ k: Double, _ alpha: Double) -> Color {
                switch colourMode {
                case 1: return sweep[Int(k * Double(sweep.count - 1))].opacity(alpha)
                case 2: return first.opacity(alpha)
                default: return Color.white.opacity(alpha)
                }
            }
            // Orbit paths: faint rings the Working / Weaving states move on.
            if orbits > 0, state == 0 || state == 5 {
                for i in 0..<3 {
                    var path = Path()
                    let tilt = Double(i) * 1.05 + 0.4
                    for k in 0...72 {
                        let a = Double(k) / 72 * 2 * .pi
                        let p = Self.ring(a, tilt: tilt, spin: t * (0.3 + Double(i) * 0.15), R: R)
                        let pt = CGPoint(x: c.x + p.x, y: c.y + p.y)
                        if k == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                    ctx.stroke(path, with: .color(.white.opacity(0.12 * orbits)), lineWidth: 0.8)
                }
            }
            ctx.blendMode = .plusLighter
            var positions: [CGPoint] = []
            positions.reserveCapacity(count)
            for (i, d) in Self.dots.prefix(count).enumerated() {
                var p = CGPoint.zero
                var depth = 1.0
                switch state {
                case 0: // Working — three tilted rings, like an atom.
                    let ring = i % 3
                    let tilt = Double(ring) * 1.05 + 0.4
                    let q = Self.ring(d.a + t * (0.5 + Double(ring) * 0.2), tilt: tilt, spin: t * (0.3 + Double(ring) * 0.15), R: R * (0.85 + 0.15 * d.r))
                    p = CGPoint(x: q.x, y: q.y); depth = q.z
                case 1: // Searching — a sweep: dots along spiral arms, a bright wedge scanning round.
                    let arm = Double(i % 4) / 4 * 2 * .pi
                    let rr = d.r * R
                    let a = arm + rr / R * 2.2 + t * 0.6
                    p = CGPoint(x: cos(a) * rr, y: sin(a) * rr)
                    let wedge = (a - t * 1.8).truncatingRemainder(dividingBy: 2 * .pi)
                    depth = 0.4 + 0.6 * max(0, cos(wedge))
                case 2: // Solving — waves converging and diverging.
                    let phase = sin(t * 1.4 - d.r * 4)
                    let rr = R * (0.25 + 0.7 * d.r) * (0.75 + 0.25 * phase)
                    p = CGPoint(x: cos(d.a + t * 0.2) * rr, y: sin(d.a + t * 0.2) * rr)
                    depth = 0.5 + 0.5 * phase
                case 3: // Listening — rings rippling inward from the rim, more with audio.
                    let ripple = 1 - ((t * 0.5 + d.k) .truncatingRemainder(dividingBy: 1))
                    let rr = R * (0.3 + 0.7 * ripple) * (1 + audio * 0.2)
                    p = CGPoint(x: cos(d.a) * rr, y: sin(d.a) * rr)
                    depth = ripple
                case 4: // Connecting — a slow drift; lines drawn between neighbours below.
                    let x = sin(t * 0.3 * d.s + d.a) * 0.8, y = cos(t * 0.25 * d.s + d.b) * 0.8
                    p = CGPoint(x: x * R, y: y * R)
                case 5: // Weaving — figure-eights, phased.
                    let u = t * 0.8 * d.s + d.a
                    let q = Self.ring(u, tilt: 0.9, spin: t * 0.2, R: R)
                    p = CGPoint(x: q.x * cos(u * 0.5), y: q.y)
                    depth = q.z
                case 6: // Composing — dots settle onto a lattice, then scatter.
                    let n = Int(ceil(sqrt(Double(count))))
                    let gx = Double(i % n) / Double(max(n - 1, 1)) - 0.5, gy = Double(i / n) / Double(max(n - 1, 1)) - 0.5
                    let settle = 0.5 + 0.5 * sin(t * 0.6)
                    let sx = sin(d.a + t * 0.4) * 0.8, sy = cos(d.b + t * 0.3) * 0.8
                    p = CGPoint(x: (gx * 1.5 * settle + sx * (1 - settle)) * R, y: (gy * 1.5 * settle + sy * (1 - settle)) * R)
                    depth = 0.6 + 0.4 * settle
                case 7: // Breathing — the cloud swelling and settling.
                    let breath = 0.75 + 0.25 * sin(t * 0.9) + audio * 0.2
                    let rr = R * d.r * breath
                    p = CGPoint(x: cos(d.a) * rr * 0.9 + sin(d.b) * 5, y: sin(d.a) * rr * 0.9)
                    depth = 0.5 + 0.5 * d.r
                default: // Shaping — the outline morphing circle → square → circle.
                    let m = 0.5 + 0.5 * sin(t * 0.7)
                    let ca = cos(d.a), sa = sin(d.a)
                    let sq = max(abs(ca), abs(sa))
                    let rr = R * 0.9 * (1 - m + m / max(sq, 0.001) * 0.72) * (0.85 + 0.15 * d.r)
                    p = CGPoint(x: ca * rr, y: sa * rr)
                }
                let pt = CGPoint(x: c.x + p.x, y: c.y + p.y)
                positions.append(pt)
                let s = dotSize * d.s * (0.5 + 0.5 * depth) * (1 + audio * 0.3)
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - s / 2, y: pt.y - s / 2, width: s, height: s)), with: .color(color(d.k, 0.35 + 0.65 * depth)))
            }
            if state == 4 {
                // Connecting: short lines between close neighbours.
                let maxD = R * 0.28
                for i in 0..<positions.count {
                    for j in (i + 1)..<positions.count {
                        let dd = hypot(positions[i].x - positions[j].x, positions[i].y - positions[j].y)
                        guard dd < maxD else { continue }
                        var path = Path()
                        path.move(to: positions[i]); path.addLine(to: positions[j])
                        ctx.stroke(path, with: .color(color(Self.dots[i].k, (1 - dd / maxD) * 0.5)), lineWidth: 0.8)
                    }
                }
            }
            // Particles: a few brighter sparkles drifting through.
            for k in 0..<particles {
                let fk = Double(k)
                let a = t * 0.5 + fk * 2.1, rr = R * (0.3 + 0.6 * (0.5 + 0.5 * sin(t * 0.7 + fk)))
                let pt = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a * 1.3) * rr)
                let s = dotSize * 1.8
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - s / 2, y: pt.y - s / 2, width: s, height: s)), with: .color(color(fk / 3, 0.9)))
            }
        }
        .frame(width: frame.diameter, height: frame.diameter)
    }

    /// A point on a tilted ring, rotated about Y — returns x, y in the
    /// plane and z for depth.
    private static func ring(_ a: Double, tilt: Double, spin: Double, R: Double) -> (x: Double, y: Double, z: Double) {
        let x0 = cos(a) * R, y0 = sin(a) * R * cos(tilt), z0 = sin(a) * R * sin(tilt)
        let x = x0 * cos(spin) + z0 * sin(spin), z = -x0 * sin(spin) + z0 * cos(spin)
        return (x, y0, (z / R + 1) / 2)
    }
}
