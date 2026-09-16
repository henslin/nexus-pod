import SwiftUI

// Bloom, brought into the Lab (Chris, 2026-09-15: "a really cool,
// fullscreen ethereal way to interact with an agent"). The Bloom app's
// source is gone; this is rebuilt from the surviving build: a sunflower
// head seen from above — Vogel's phyllotaxis, r = c√n at the golden
// angle — as grey dots on white, and *disturbances*: blooms of colour
// that open somewhere in the field, swell the dots under them, and fade.
// Here the blooms come on the clock, on a tap where you tap, and on the
// voice — a ripple from the centre whose height is the level, and a new
// bloom on each beat. The transcript rides along the bottom.

// MARK: - The field

struct LabSunflowerView: View {
    let frame: LabFrame
    @ObservedObject var config: RingConfig

    /// A bloom you caused — a tap, or a beat. The clock's own blooms
    /// need no state; these do.
    private struct Seed: Equatable {
        var at: Double        // frame time it opened
        var x: Double, y: Double  // 0…1 of the canvas
        var color: Int
        var strength: Double
    }
    @State private var seeds: [Seed] = []
    @State private var lastBeatAt: Double = -10

    private static let goldenAngle = Double.pi * (3 - 5.0.squareRoot())

    private static func hash(_ k: Double) -> Double {
        let v = sin(k * 12.9898 + 78.233) * 43758.5453
        return v - floor(v)
    }

    private struct Bloom { var x: Double; var y: Double; var r: Double; var strength: Double; var color: Color }

    /// Every bloom alive now: the clock's, then yours. Positions are
    /// fractions of the canvas; radius in points.
    private func activeBlooms(t: Double, rate: Double, life: Double, radius: Double, colors: [Color]) -> [Bloom] {
        var blooms: [Bloom] = []
        let n = max(colors.count, 1)
        if rate > 0 {
            let interval = 1 / rate
            let first = max(0, Int((t - life) / interval)), last = Int(t / interval)
            if last >= first {
                for k in first...last {
                    let born = Double(k) * interval + Self.hash(Double(k) + 0.5) * interval * 0.6
                    let age = t - born
                    guard age >= 0, age < life else { continue }
                    let u = age / life
                    let env = pow(sin(u * .pi), 0.8)
                    blooms.append(Bloom(x: 0.1 + 0.8 * Self.hash(Double(k) * 1.7 + 1), y: 0.08 + 0.84 * Self.hash(Double(k) * 2.3 + 2),
                                        r: radius * (0.45 + 0.55 * u), strength: env, color: colors[k % n]))
                }
            }
        }
        for s in seeds {
            let age = t - s.at
            guard age >= 0, age < life else { continue }
            let u = age / life
            blooms.append(Bloom(x: s.x, y: s.y, r: radius * (0.35 + 0.65 * u) * (0.7 + 0.6 * s.strength),
                                strength: pow(sin(u * .pi), 0.8) * (0.6 + 0.6 * s.strength), color: colors[s.color % n]))
        }
        return blooms
    }

    /// Every knob, read once per frame.
    private struct Knobs {
        var spacing, dot, growth, cx, cy, breathe, glow: Double
        var dark: Bool
        var rate, life, radius, grow, tint, core, wave, waveSpeed: Double
        var spawn: Bool
        var threshold: Double
        var heroOn: Bool
        var heroSize: Double
        var transcriptOn: Bool
        var textSize, textGlow: Double
        init(_ f: LabFrame) {
            spacing = f.p("spacing", .sunflower); dot = f.p("dot", .sunflower); growth = f.p("growth", .sunflower)
            cx = f.p("centerX", .sunflower); cy = f.p("centerY", .sunflower); breathe = f.p("breathe", .sunflower)
            let ground = Int(f.p("ground", .sunflower))
            dark = ground == 0 ? f.darkStage : ground == 2
            glow = f.p("glow", .sunflower)
            rate = f.p("rate", .sunflower); life = max(f.p("life", .sunflower), 0.5)
            radius = f.p("radius", .sunflower); grow = f.p("grow", .sunflower)
            tint = f.p("tint", .sunflower); core = f.p("core", .sunflower)
            wave = f.p("wave", .sunflower); waveSpeed = f.p("waveSpeed", .sunflower)
            spawn = f.p("spawn", .sunflower) >= 0.5; threshold = f.p("threshold", .sunflower)
            heroOn = f.p("hero", .sunflower) >= 0.5; heroSize = f.p("heroSize", .sunflower)
            transcriptOn = f.p("transcript", .sunflower) >= 0.5
            textSize = f.p("textSize", .sunflower); textGlow = f.p("textGlow", .sunflower)
        }
    }

    var body: some View {
        let k = Knobs(frame)
        let t = frame.time
        let blooms = activeBlooms(t: t, rate: k.rate, life: k.life, radius: k.radius, colors: frame.colors)
        LabPhoneCanvas(frame: frame) { size in
            field(size: size, k: k, blooms: blooms)
        }
        // A tap opens a bloom where you tapped; a beat, where the voice
        // lands (somewhere — it has no place, so a hashed one).
        .onChange(of: frame.taps) { _, _ in
            let p = frame.pointer
            let size = LabPhoneCanvas<EmptyView>.size(for: frame)
            let x = p.map { min(1, max(0, Double($0.x / size.width + 0.5))) } ?? Self.hash(t)
            let y = p.map { min(1, max(0, Double($0.y / size.height + 0.5))) } ?? Self.hash(t + 1)
            seeds.append(Seed(at: t, x: x, y: y, color: seeds.count + 3, strength: 1))
            seeds.removeAll { t - $0.at > k.life }
        }
        .onChange(of: frame.audio) { _, level in
            guard k.spawn, level > k.threshold, t - lastBeatAt > 0.45 else { return }
            lastBeatAt = t
            seeds.append(Seed(at: t, x: 0.15 + 0.7 * Self.hash(t * 3.1), y: 0.1 + 0.75 * Self.hash(t * 5.7 + 9), color: seeds.count + 1, strength: min(1, level)))
            seeds.removeAll { t - $0.at > k.life }
        }
    }

    /// The dots, the hero, the transcript.
    private func field(size: CGSize, k: Knobs, blooms: [Bloom]) -> some View {
        let t = frame.time
        let voice = frame.audio
        let colors = frame.colors
        let center = CGPoint(x: size.width * k.cx, y: size.height * k.cy)
        let corner = max(hypot(center.x, center.y), hypot(size.width - center.x, center.y),
                         hypot(center.x, size.height - center.y), hypot(size.width - center.x, size.height - center.y))
        let count = Int((corner / k.spacing) * (corner / k.spacing)) + 1
        // Dark mode is not the light one inverted: the dots sit dim and
        // the blooms *light* them — a halo under the field, and dots
        // near a bloom's core going past the colour toward white.
        let baseGrey = k.dark ? Color(white: 0.2) : Color(white: 0.78)
        let halo = k.dark ? k.glow : 0
        let heroD = size.width * k.heroSize
        let ringR = (t * k.waveSpeed).truncatingRemainder(dividingBy: corner + 60)
        let breath = 1 + k.breathe * 0.08 * sin(t * 1.1)

        return ZStack {
            (k.dark ? Color(white: 0.04) : Color.white)
            Canvas { ctx, _ in
                // The halos, under the dots.
                if halo > 0 {
                    for b in blooms {
                        let c = CGPoint(x: CGFloat(b.x) * size.width, y: CGFloat(b.y) * size.height)
                        let rr = CGFloat(b.r) * 1.25
                        let g = Gradient(stops: [.init(color: b.color.opacity(0.5 * b.strength * halo), location: 0),
                                                 .init(color: b.color.opacity(0.12 * b.strength * halo), location: 0.45),
                                                 .init(color: b.color.opacity(0), location: 1)])
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)),
                                 with: .radialGradient(g, center: c, startRadius: 0, endRadius: rr))
                    }
                    // The voice's ripple casts a faint ring too.
                    if k.wave > 0, voice > 0.05, ringR > 1, let c0 = colors.first {
                        // A soft annulus: clear at the ring's inner and
                        // outer edge, the colour at the ring itself.
                        let band = 30 * k.wave
                        let outer = ringR + band
                        let mid = ringR / outer, inner = max(0, ringR - band) / outer
                        let g = Gradient(stops: [.init(color: c0.opacity(0), location: inner),
                                                 .init(color: c0.opacity(0.3 * voice * halo), location: mid),
                                                 .init(color: c0.opacity(0), location: 1)])
                        ctx.fill(Path(ellipseIn: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2)),
                                 with: .radialGradient(g, center: center, startRadius: 0, endRadius: outer))
                    }
                }
                for n in 0..<count {
                    let r = k.spacing * Double(n).squareRoot()
                    let a = Double(n) * Self.goldenAngle
                    let x = center.x + CGFloat(cos(a) * r), y = center.y + CGFloat(sin(a) * r)
                    guard x > -8, y > -8, x < size.width + 8, y < size.height + 8 else { continue }
                    let edge = r / corner
                    var scale = (0.35 + 0.65 * edge) * (1 + k.growth * edge) * breath
                    var color = baseGrey
                    var mixed = 0.0
                    var bloomColor: Color?
                    for b in blooms {
                        let d = hypot(x - CGFloat(b.x) * size.width, y - CGFloat(b.y) * size.height)
                        guard d < CGFloat(b.r) else { continue }
                        let q = 1 - Double(d) / b.r
                        let w = b.strength * q * q * (1 + k.core * q * q)
                        if w > mixed { mixed = w; bloomColor = b.color }
                        scale *= 1 + k.grow * w * 0.6
                    }
                    // The voice's ripple: a ring from the centre.
                    if k.wave > 0, voice > 0.02 {
                        let dr = abs(r - ringR)
                        let w = max(0, 1 - dr / 40) * voice * k.wave
                        scale *= 1 + w * 0.9
                        if w * 0.6 > mixed { mixed = w * 0.6; bloomColor = colors.first }
                    }
                    if let bloomColor, mixed > 0.01 {
                        color = Self.mix(baseGrey, bloomColor, min(1, mixed) * k.tint)
                        // Lit: past the colour, toward white, at the core.
                        if k.dark { color = Self.mix(color, .white, min(1, max(0, mixed - 0.5)) * 0.7 * k.glow) }
                    }
                    // Under the hero, the field clears.
                    if k.heroOn {
                        let dh = hypot(x - center.x, y - center.y)
                        if dh < heroD * 0.62 { scale *= max(0, (dh - heroD * 0.45) / (heroD * 0.17)) }
                    }
                    let rad = CGFloat(k.dot * scale)
                    guard rad > 0.2 else { continue }
                    ctx.fill(Path(ellipseIn: CGRect(x: x - rad, y: y - rad, width: rad * 2, height: rad * 2)), with: .color(color))
                }
            }
            if k.heroOn {
                LabHeroView(frame: frame, config: config, diameter: heroD)
                    .position(center)
            }
            if k.transcriptOn {
                VStack {
                    Spacer()
                    LabTranscriptView(frame: frame, width: size.width - 48, size: k.textSize, glow: k.textGlow, dark: k.dark)
                        .frame(height: 130)
                        .padding(.bottom, 44)
                }
            }
        }
    }

    private static func mix(_ a: Color, _ b: Color, _ k: Double) -> Color {
        let ra = PerceptualGradient.rgb(a), rb = PerceptualGradient.rgb(b)
        return Color(red: ra.red + (rb.red - ra.red) * k, green: ra.green + (rb.green - ra.green) * k, blue: ra.blue + (rb.blue - ra.blue) * k)
    }
}

// MARK: - The transcript

/// The live transcript, word by word: each word arrives blurred and
/// bright and settles; older words dim. Sample copy runs until the mic
/// and the transcript are on, so the design reads without a voice.
struct LabTranscriptView: View {
    let frame: LabFrame
    let width: CGFloat
    let size: Double
    let glow: Double
    var dark: Bool = true

    var body: some View {
        if frame.transcribing, !frame.transcript.isEmpty {
            live
        } else {
            VStack(spacing: 8) {
                LabCaptionWords(frame: frame, width: width, size: size, style: 1, rate: 3.5, glow: glow, hold: 5)
                    .environment(\.labTextOnDark, dark)
                if !frame.transcribing {
                    Text("Audio Reactive + Live Transcript for your own words")
                        .font(.caption2)
                        .foregroundStyle(dark ? Color.white.opacity(0.4) : Color.black.opacity(0.35))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(width: width)
                }
            }
        }
    }

    private var live: some View {
        let words = Array(frame.transcript.suffix(16))
        let primary = frame.colors.first ?? .white
        let lines = wrap(words.map(\.text))
        return VStack(alignment: .center, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 6) {
                    ForEach(line, id: \.index) { w in
                        let age = words[w.index].age
                        let isNew = age < 0.4
                        Text(w.text)
                            .font(.system(size: size, weight: .medium))
                            .foregroundStyle(dark ? Color.white : Color(white: 0.12))
                            .opacity(min(1, max(0, age * 5 + 0.15)) * (age > 8 ? max(0.3, 1 - (age - 8) / 8) : 1))
                            .blur(radius: isNew ? (0.4 - age) * 18 : 0)
                            .shadow(color: primary.opacity(isNew ? glow : glow * 0.2), radius: isNew ? 12 : 4)
                    }
                }
            }
        }
        .frame(width: width)
        .animation(.easeOut(duration: 0.3), value: words.count)
    }

    private struct Word: Identifiable { let index: Int; let text: String; var id: Int { index } }

    private func wrap(_ words: [String]) -> [[Word]] {
        var lines: [[Word]] = [[]]
        var lineWidth: CGFloat = 0
        let charWidth = CGFloat(size) * 0.55
        for (i, w) in words.enumerated() {
            let ww = CGFloat(w.count) * charWidth + 6
            if lineWidth + ww > width, !lines[lines.count - 1].isEmpty {
                lines.append([])
                lineWidth = 0
            }
            lines[lines.count - 1].append(Word(index: i, text: w))
            lineWidth += ww
        }
        // The bottom lines are the newest; keep three.
        return Array(lines.suffix(3))
    }
}

/// Whether text in a flow sits on a dark ground — Bloom's white field
/// needs dark words, and `LabCaptionWords` was written for white.
struct LabTextOnDarkKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var labTextOnDark: Bool {
        get { self[LabTextOnDarkKey.self] }
        set { self[LabTextOnDarkKey.self] = newValue }
    }
}
