import SwiftUI

// The flow labs: what happens when you tap the Nexus tab, on a phone
// canvas with the real app behind it. These are about the whole screen,
// so they draw a phone rather than a disc, and the tappable ones advance
// on a tap — the question is answered by asking it.

// MARK: - Phone canvas

/// A phone-shaped canvas with the demo app's dashboard screenshot behind
/// whatever the flow draws. Sized from the stage's diameter so the Size
/// slider still means something.
struct LabPhoneCanvas<Content: View>: View {
    let frame: LabFrame
    @ViewBuilder let content: (CGSize) -> Content

    static func size(for frame: LabFrame) -> CGSize {
        let w = max(200, frame.diameter * 0.85)
        return CGSize(width: w, height: w * 2.05)
    }

    var body: some View {
        let size = Self.size(for: frame)
        let corner = size.width * 0.13
        ZStack {
            DemoTab.dashboard.screenshotImage(dark: frame.darkStage)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
            content(size)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
            .strokeBorder(Color.white.opacity(frame.darkStage ? 0.12 : 0.35), lineWidth: 1))
    }
}

extension LabFrame {
    /// The flow's current stage: clock-driven when Auto is on, plus one
    /// per tap, modulo the stage count — so a tap always moves on from
    /// wherever the clock has it.
    func stage(of experiment: LabExperiment, count: Int) -> Int {
        let hold = max(p("hold", experiment), 0.2)
        let auto = p("auto", experiment) >= 0.5
        let clock = auto ? Int(time / hold) : 0
        return ((clock + taps) % count + count) % count
    }

    func spring(of experiment: LabExperiment) -> Animation {
        .spring(response: p("spring", experiment), dampingFraction: 1 - p("bounce", experiment) * 0.45)
    }
}

// MARK: - Journey: pod → chat → voice

struct LabJourneyView: View {
    let frame: LabFrame
    @ObservedObject var config: RingConfig

    private enum Stage: Int { case pod, chat, voice }

    var body: some View {
        let stage = Stage(rawValue: frame.stage(of: .journey, count: 3)) ?? .pod
        let spring = frame.spring(of: .journey)
        LabPhoneCanvas(frame: frame) { size in
            ZStack {
                // The app dims behind the sheet and goes dark for voice.
                Color.black
                    .opacity(stage == .pod ? 0 : stage == .chat ? frame.p("dim", .journey) * 0.7 : 0.92)
                    .animation(spring, value: stage)

                // Edge glow, voice stage only.
                LabEdgeGlowStroke(frame: frame,
                                  size: size,
                                  width: 18, blur: 20,
                                  strength: stage == .voice ? frame.p("glow", .journey) : 0,
                                  rotate: 0.3, inset: 0)
                    .animation(spring, value: stage)

                // The tab bar, present until voice takes over.
                VStack {
                    Spacer()
                    TabBarPreview(config: config, selectedTab: .constant(.dashboard), width: size.width - 32)
                        .allowsHitTesting(false)
                        .padding(.bottom, 24)
                        .opacity(stage == .voice ? 0 : 1)
                        .offset(y: stage == .voice ? 80 : 0)
                        .animation(spring, value: stage)
                }

                // One glass panel: the pod, then the sheet, then the whole
                // screen. Its frame and corner animate, so it is one thing
                // growing — the Liquid Glass morph.
                let panel = panelFrame(stage, size)
                glassPanel(stage: stage, size: size, panel: panel, spring: spring)
                    .frame(width: panel.width, height: panel.height)
                    .position(x: panel.midX, y: panel.midY)
                    .animation(spring, value: stage)

                // The ring, one view, moving between its three homes.
                let ringFrame = ringFrame(stage, size)
                LabHeroView(frame: frame, config: config, diameter: ringFrame.width)
                    .position(x: ringFrame.midX, y: ringFrame.midY)
                    .animation(spring, value: stage)
            }
        }
    }

    private var podCenter: (CGSize) -> CGPoint {
        { size in
            // Mirrors `TabBarPreview`: bar is `width - 32` wide, centred; the
            // pod is the trailing 62pt of it; 24pt above the bottom.
            let pod = CGFloat(RingConfig.tabBarPodDiameter)
            return CGPoint(x: 16 + (size.width - 32) - pod / 2, y: size.height - 24 - pod / 2)
        }
    }

    private func panelFrame(_ stage: Stage, _ size: CGSize) -> CGRect {
        let pod = CGFloat(RingConfig.tabBarPodDiameter)
        switch stage {
        case .pod:
            let c = podCenter(size)
            return CGRect(x: c.x - pod / 2, y: c.y - pod / 2, width: pod, height: pod)
        case .chat:
            let h = size.height * frame.p("sheet", .journey)
            return CGRect(x: 0, y: size.height - h, width: size.width, height: h)
        case .voice:
            return CGRect(origin: .zero, size: size)
        }
    }

    private func ringFrame(_ stage: Stage, _ size: CGSize) -> CGRect {
        let pod = CGFloat(RingConfig.tabBarPodDiameter)
        switch stage {
        case .pod:
            let c = podCenter(size)
            return CGRect(x: c.x - pod / 2, y: c.y - pod / 2, width: pod, height: pod)
        case .chat:
            let panel = panelFrame(.chat, size)
            switch Int(frame.p("role", .journey)) {
            case 0:  // hero above the messages
                return CGRect(x: size.width / 2 - 50, y: panel.minY + 28, width: 100, height: 100)
            case 1:  // avatar on the first reply
                return CGRect(x: 20, y: panel.minY + 60, width: 40, height: 40)
            default: // the input's voice button
                return CGRect(x: size.width - 16 - 44, y: panel.maxY - 16 - 44, width: 44, height: 44)
            }
        case .voice:
            let d = size.width * frame.p("hero", .journey)
            return CGRect(x: size.width / 2 - d / 2, y: size.height * 0.42 - d / 2, width: d, height: d)
        }
    }

    @ViewBuilder
    private func glassPanel(stage: Stage, size: CGSize, panel: CGRect, spring: Animation) -> some View {
        let corner: CGFloat = stage == .pod ? 31 : stage == .chat ? 34 : size.width * 0.13
        let role = Int(frame.p("role", .journey))
        ZStack(alignment: .top) {
            if stage == .chat {
                VStack(alignment: .leading, spacing: 12) {
                    if role == 0 { Spacer().frame(height: 110) } else { Spacer().frame(height: 22) }
                    HStack(alignment: .top, spacing: 10) {
                        if role == 1 { Spacer().frame(width: 48) }
                        bubble("How can I help?", mine: false)
                        Spacer(minLength: 20)
                    }
                    HStack {
                        Spacer(minLength: 40)
                        bubble("Is anyone home?", mine: true)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        if role == 1 { Spacer().frame(width: 48) }
                        bubble("John arrived home at 5:42. The front door is locked and the living room lights are on.", mine: false)
                        Spacer(minLength: 20)
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        Text("Message")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 44)
                            .background(Capsule().fill(.fill.tertiary))
                        Spacer().frame(width: role == 2 ? 44 : 0)
                    }
                }
                .padding(16)
                .transition(.opacity)
            }
            if stage == .voice {
                VStack(spacing: 10) {
                    Spacer()
                    Text("Listening…")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    LabCaptionWords(frame: frame, width: size.width - 48, size: 22, style: 1, rate: 4, glow: 0.4, hold: 4)
                        .frame(height: 120)
                    Spacer().frame(height: 60)
                }
                .transition(.opacity)
            }
        }
        .modifier(LabGlassShape(cornerRadius: corner, glass: config.glass))
        .environment(\.colorScheme, stage == .voice ? .dark : (frame.darkStage ? .dark : .light))
    }

    private func bubble(_ text: String, mine: Bool) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(mine ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(mine ? AnyShapeStyle(config.primaryColor) : AnyShapeStyle(.fill.tertiary)))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// `.glassEffect` behind an availability gate, as a modifier. Shared by
/// the flows (was private to Morph).
struct LabGlassShape: ViewModifier {
    let cornerRadius: CGFloat
    let glass: Glass

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(glass, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

// MARK: - Agent States: idle / listening / thinking / speaking

struct LabAgentStatesView: View {
    let frame: LabFrame
    @ObservedObject var config: RingConfig

    private static let names = ["Idle", "Listening", "Thinking", "Speaking"]

    var body: some View {
        let stage = frame.stage(of: .agentStates, count: 4)
        let spring = frame.spring(of: .agentStates)
        let t = frame.time
        let voice = max(frame.audio, synthVoice(t))
        LabPhoneCanvas(frame: frame) { size in
            ZStack {
                Color.black.opacity(0.75)
                let d = size.width * 0.5
                // Idle: breathes. Listening: opens (scales up) and a soft
                // halo follows the voice. Thinking: a comet orbits.
                // Speaking: pulses per syllable.
                let scale: CGFloat = {
                    switch stage {
                    case 0: return 1 + CGFloat(sin(t * 1.2)) * frame.p("breath", .agentStates)
                    case 1: return 1 + frame.p("open", .agentStates) * (0.6 + voice * 0.6)
                    case 2: return 0.9
                    default: return 1 + frame.p("pulse", .agentStates) * voice
                    }
                }()
                // Halo
                Circle()
                    .strokeBorder(config.primaryColor.opacity(stage == 1 ? 0.35 + voice * 0.4 : 0), lineWidth: 6)
                    .frame(width: d * 1.35 * (1 + voice * 0.25), height: d * 1.35 * (1 + voice * 0.25))
                    .blur(radius: 8)
                    .animation(spring, value: stage)
                LabHeroView(frame: frame, config: config, diameter: d * 1.3)
                    .scaleEffect(scale)
                    .animation(spring, value: stage)
                // Comet
                if stage == 2 {
                    let a = t * frame.p("orbit", .agentStates) * 2
                    let r = d * 0.62
                    ForEach(0..<6, id: \.self) { i in
                        let ai = a - Double(i) * 0.18
                        Circle()
                            .fill(config.secondaryColor.opacity(1 - Double(i) * 0.15))
                            .frame(width: 10 - CGFloat(i), height: 10 - CGFloat(i))
                            .offset(x: cos(ai) * r, y: sin(ai) * r)
                    }
                    .transition(.opacity)
                }
                VStack {
                    Spacer()
                    Text(Self.names[stage])
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(spring, value: stage)
                    Text("Tap to advance")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.bottom, 40)
                }
            }
        }
    }

    /// A speech-like envelope: syllables at ~4/s, phrases at ~0.4/s.
    private func synthVoice(_ t: Double) -> Double {
        let syllable = max(0, sin(t * 4 * 2 * .pi)) * max(0, sin(t * 0.9 + 1))
        let phrase = 0.5 + 0.5 * sin(t * 0.4)
        return syllable * phrase * 0.9
    }
}

// MARK: - Waveform

struct LabWaveformView: View {
    let frame: LabFrame
    @ObservedObject var config: RingConfig

    var body: some View {
        let style = Int(frame.p("style", .waveform))
        let bars = Int(frame.p("bars", .waveform))
        let height = frame.p("height", .waveform)
        let thickness = frame.p("thickness", .waveform)
        let smooth = frame.p("smooth", .waveform)
        let mirror = frame.p("mirror", .waveform) >= 0.5
        let synth = frame.p("synth", .waveform)
        let energies = Self.energies(frame: frame, count: bars, smooth: smooth, synth: synth)
        let sweep = PerceptualGradient.closedSweep(through: frame.colors.map(PerceptualGradient.rgb), count: max(bars, 2))
        LabPhoneCanvas(frame: frame) { size in
            ZStack {
                Color.black.opacity(0.75)
                if style == 2 {
                    LabHeroView(frame: frame, config: config, diameter: size.width * 0.4)
                }
                Canvas { ctx, area in
                    let c = CGPoint(x: area.width / 2, y: area.height / 2)
                    switch style {
                    case 1:
                        // Line: the energies as a smooth polyline, mirrored.
                        var path = Path()
                        let w = area.width * 0.8, x0 = c.x - w / 2, amp = area.height * 0.25 * height
                        for (i, e) in energies.enumerated() {
                            let x = x0 + w * CGFloat(i) / CGFloat(max(bars - 1, 1))
                            let y = c.y - amp * CGFloat(e) * CGFloat(sin(Double(i) * 0.7 + frame.time * 6))
                            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                        ctx.stroke(path, with: .linearGradient(Gradient(colors: sweep), startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: x0 + w, y: 0)),
                                   style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round))
                    case 2:
                        // Ring of bars round the pod.
                        let r0 = area.width * 0.24
                        for (i, e) in energies.enumerated() {
                            let a = Double(i) / Double(bars) * 2 * .pi - .pi / 2
                            let len = area.width * 0.2 * height * CGFloat(e) + 3
                            var p = Path()
                            p.move(to: CGPoint(x: c.x + cos(a) * r0, y: c.y + sin(a) * r0))
                            p.addLine(to: CGPoint(x: c.x + cos(a) * (r0 + len), y: c.y + sin(a) * (r0 + len)))
                            ctx.stroke(p, with: .color(sweep[i % sweep.count]), style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                        }
                    default:
                        // Bars.
                        let w = area.width * 0.8, x0 = c.x - w / 2
                        let gap = w / CGFloat(bars)
                        let amp = area.height * 0.25 * height
                        for (i, e) in energies.enumerated() {
                            let x = x0 + gap * (CGFloat(i) + 0.5)
                            let h = max(thickness, amp * CGFloat(e))
                            let rect = mirror
                                ? CGRect(x: x - thickness / 2, y: c.y - h, width: thickness, height: h * 2)
                                : CGRect(x: x - thickness / 2, y: c.y + amp - h * 2, width: thickness, height: h * 2)
                            ctx.fill(Path(roundedRect: rect, cornerRadius: thickness / 2), with: .color(sweep[i % sweep.count]))
                        }
                    }
                }
            }
        }
    }

    /// Per-bar energy from the spectrum — bass on the left, treble on the
    /// right — or a synthetic voice when there is no audio, smoothed
    /// across neighbours.
    static func energies(frame: LabFrame, count: Int, smooth: Double, synth: Double) -> [Double] {
        let b = frame.bands
        let live = b.bass + b.mid + b.treble > 0.01
        var out = (0..<count).map { i -> Double in
            let x = Double(i) / Double(max(count - 1, 1))
            if live {
                // Interpolate bass→mid→treble across the bars, with a
                // little per-bar noise so equal bands don't draw a slab.
                let e = x < 0.5 ? b.bass + (b.mid - b.bass) * x * 2 : b.mid + (b.treble - b.mid) * (x - 0.5) * 2
                return e * (0.75 + 0.25 * sin(Double(i) * 1.7 + frame.time * 9))
            } else {
                let syll = max(0, sin(frame.time * 4.2 * 2 * .pi + Double(i) * 0.3)) * max(0, sin(frame.time * 0.9 + 1))
                let shape = 1 - abs(x - 0.5) * 1.4
                return synth * syll * shape * (0.6 + 0.4 * sin(Double(i) * 2.1 + frame.time * 7))
            }
        }
        if smooth > 0, count > 2 {
            let k = smooth * 0.5
            let src = out
            for i in 0..<count {
                let l = src[max(i - 1, 0)], r = src[min(i + 1, count - 1)]
                out[i] = src[i] * (1 - k) + (l + r) * k / 2
            }
        }
        return out.map { min(max($0, 0), 1.2) }
    }
}

// MARK: - Edge Glow

/// The glow itself, reusable — Journey uses it in its voice stage.
struct LabEdgeGlowStroke: View {
    let frame: LabFrame
    let size: CGSize
    let width: Double
    let blur: Double
    let strength: Double
    let rotate: Double
    let inset: Double

    var body: some View {
        let corner = size.width * 0.13 - inset * 0.5
        let sweep = PerceptualGradient.closedSweep(through: frame.colors.map(PerceptualGradient.rgb), count: 48)
        let breathe = 0.85 + 0.15 * sin(frame.time * 1.5)
        let gradient = AngularGradient(colors: sweep, center: .center, angle: .degrees(frame.time * rotate * 60))
        let shape = RoundedRectangle(cornerRadius: max(corner, 8), style: .continuous)
        // Two strokes: a wide blurred band for the glow and a thin sharp
        // line at the edge so it reads as light *coming from* the edge.
        // Additive, so the band brightens what is under it rather than
        // tinting it — the blurred stroke alone was a faint wash.
        ZStack {
            shape.strokeBorder(gradient, lineWidth: width)
                .padding(inset)
                .blur(radius: blur)
                .opacity(1.0)
            shape.strokeBorder(gradient, lineWidth: width * 0.5)
                .padding(inset)
                .blur(radius: blur * 0.35)
                .opacity(0.9)
            shape.strokeBorder(gradient, lineWidth: 2)
                .padding(inset)
                .opacity(0.9)
        }
        .blendMode(.plusLighter)
        .opacity(strength * breathe * (0.75 + frame.audio * 0.5))
        .frame(width: size.width, height: size.height)
    }
}

struct LabEdgeGlowView: View {
    let frame: LabFrame
    @ObservedObject var config: RingConfig

    var body: some View {
        LabPhoneCanvas(frame: frame) { size in
            ZStack {
                Color.black.opacity(0.85)
                LabEdgeGlowStroke(frame: frame, size: size,
                                  width: frame.p("width", .edgeGlow),
                                  blur: frame.p("blur", .edgeGlow),
                                  strength: 0.6 + frame.p("breathe", .edgeGlow) * 0.4 * (0.5 + 0.5 * sin(frame.time * 2)),
                                  rotate: frame.p("rotate", .edgeGlow),
                                  inset: frame.p("inset", .edgeGlow))
                let hero = frame.p("ringSize", .edgeGlow)
                if hero > 0 {
                    LabHeroView(frame: frame, config: config, diameter: size.width * hero * 1.3)
                }
            }
        }
    }
}

// MARK: - Caption

/// Words arriving over time. Reused by Journey's voice stage.
struct LabCaptionWords: View {
    let frame: LabFrame
    let width: CGFloat
    let size: Double
    let style: Int
    let rate: Double
    let glow: Double
    let hold: Double

    private static let sentences = [
        "John arrived home a few minutes ago.",
        "The front door is locked and the lights are on.",
        "Would you like me to set the thermostat?",
        "Emergency services have been called.",
    ]

    var body: some View {
        let cycle = hold
        let index = Int(frame.time / cycle) % Self.sentences.count
        let local = frame.time.truncatingRemainder(dividingBy: cycle)
        let words = Self.sentences[index].split(separator: " ").map(String.init)
        let shown = min(words.count, Int(local * rate) + 1)
        let primary = frame.colors.first ?? .white
        // A flow layout by hand: words wrap within `width`.
        let lines = Self.wrap(words.prefix(shown).map { $0 }, width: width, size: size)
        VStack(alignment: .center, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 6) {
                    ForEach(Array(line.enumerated()), id: \.offset) { _, w in
                        let age = local - Double(w.index) / rate
                        let isNew = age < 0.35
                        Text(style == 2 && w.index == shown - 1 ? String(w.text.prefix(max(1, Int(age * rate * Double(w.text.count) + 1)))) : w.text)
                            .font(.system(size: size, weight: .medium))
                            .foregroundStyle(.white)
                            .opacity(style == 0 ? min(1, max(0, age * 4 + 0.2)) : 1)
                            .blur(radius: style == 1 && isNew ? (0.35 - age) * 20 : 0)
                            .shadow(color: primary.opacity(isNew ? glow : glow * 0.25), radius: isNew ? 12 : 4)
                    }
                }
            }
        }
        .frame(width: width)
        .id(index)
        .transition(.opacity)
        .animation(.easeOut(duration: 0.3), value: shown)
    }

    private struct Word { let index: Int; let text: String }

    private static func wrap(_ words: [String], width: CGFloat, size: Double) -> [[Word]] {
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
        return lines
    }
}

struct LabCaptionView: View {
    let frame: LabFrame
    @ObservedObject var config: RingConfig

    var body: some View {
        LabPhoneCanvas(frame: frame) { size in
            ZStack {
                Color.black.opacity(0.85)
                VStack(spacing: 24) {
                    Spacer()
                    LabHeroView(frame: frame, config: config, diameter: size.width * 0.4)
                    LabCaptionWords(frame: frame, width: size.width - 48,
                                    size: frame.p("size", .caption),
                                    style: Int(frame.p("style", .caption)),
                                    rate: frame.p("rate", .caption),
                                    glow: frame.p("glow", .caption),
                                    hold: frame.p("hold", .caption))
                        .frame(height: 160)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Button Glow (UI)

struct LabButtonGlowView: View {
    let frame: LabFrame
    @ObservedObject var config: RingConfig

    var body: some View {
        let width = frame.p("width", .buttonGlow), blur = frame.p("blur", .buttonGlow)
        let rotate = frame.p("rotate", .buttonGlow), breathe = frame.p("breathe", .buttonGlow)
        let count = Int(frame.p("buttons", .buttonGlow))
        let orb = frame.p("orb", .buttonGlow)
        let sweep = PerceptualGradient.closedSweep(through: frame.colors.map(PerceptualGradient.rgb), count: 48)
        let pulse = 0.75 + 0.25 * sin(frame.time * 1.6) * breathe + frame.audio * 0.4
        LabPhoneCanvas(frame: frame) { size in
            ZStack {
                Color.black.opacity(frame.darkStage ? 0.6 : 0.15)
                VStack(spacing: 22) {
                    Spacer()
                    LabHeroView(frame: frame, config: config, diameter: size.width * orb)
                    Spacer().frame(height: 10)
                    ForEach(0..<count, id: \.self) { i in
                        let label = ["Ask Nexus", "Talk", "Send"][i % 3]
                        Text(label)
                            .font(.system(size: 17, weight: .semibold))
                            .padding(.horizontal, 28)
                            .frame(height: 52)
                            .frame(minWidth: size.width * 0.6)
                            .modifier(LabGlassShape(cornerRadius: 26, glass: config.glass))
                            .background {
                                // The glow: the palette round the capsule's
                                // edge, blurred, breathing — under the glass
                                // so the glass refracts it.
                                Capsule()
                                    .strokeBorder(AngularGradient(colors: sweep, center: .center, angle: .degrees(frame.time * rotate * 60 + Double(i) * 90)), lineWidth: width)
                                    .blur(radius: blur)
                                    .opacity(pulse)
                                    .padding(-width * 0.5)
                                    .blendMode(.plusLighter)
                            }
                    }
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Sheet (UI)

struct LabSheetView: View {
    let frame: LabFrame
    @ObservedObject var config: RingConfig

    var body: some View {
        let height = frame.p("height", .sheet)
        let hero = frame.p("hero", .sheet)
        let showWave = frame.p("waveform", .sheet) >= 0.5
        let dim = frame.p("dim", .sheet)
        LabPhoneCanvas(frame: frame) { size in
            ZStack(alignment: .bottom) {
                Color.black.opacity(dim * 0.7)
                VStack(spacing: 14) {
                    LabHeroView(frame: frame, config: config, diameter: size.width * hero)
                        .padding(.top, 22)
                    LabCaptionWords(frame: frame, width: size.width - 48, size: 17, style: 1, rate: 4, glow: 0.3, hold: 4)
                        .frame(height: 70)
                    Spacer()
                    HStack(spacing: 10) {
                        Group {
                            if showWave {
                                LabWaveformBars(frame: frame, bars: 28, height: 22)
                            } else {
                                Text("Message").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14)
                            }
                        }
                        .frame(height: 44)
                        .frame(maxWidth: .infinity)
                        .background(Capsule().fill(.fill.tertiary))
                        LabHeroView(frame: frame, config: config, diameter: 44)
                    }
                    .padding(16)
                }
                .frame(width: size.width, height: size.height * height)
                .modifier(LabGlassShape(cornerRadius: 34, glass: config.glass))
            }
        }
    }
}

/// A small inline waveform for input bars — the bars style of
/// `LabWaveformView`, at a given height.
struct LabWaveformBars: View {
    let frame: LabFrame
    let bars: Int
    let height: Double

    var body: some View {
        let energies = LabWaveformView.energies(frame: frame, count: bars, smooth: 0.5, synth: 0.6)
        let sweep = PerceptualGradient.closedSweep(through: frame.colors.map(PerceptualGradient.rgb), count: max(bars, 2))
        Canvas { ctx, size in
            let gap = size.width / CGFloat(bars)
            for (i, e) in energies.enumerated() {
                let h = max(3, height * e)
                let x = gap * (CGFloat(i) + 0.5)
                let rect = CGRect(x: x - 1.5, y: size.height / 2 - h / 2, width: 3, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(sweep[i % sweep.count]))
            }
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - Hold (Flow) — press and hold into full-screen listening

struct LabHoldView: View {
    let frame: LabFrame
    @ObservedObject var config: RingConfig

    private enum Phase { case idle, growing, listening, talking }

    var body: some View {
        let grow = frame.p("grow", .hold)
        let talk = frame.p("talk", .hold)
        let spring = Animation.spring(response: frame.p("spring", .hold), dampingFraction: 1 - frame.p("bounce", .hold) * 0.45)
        // Progress 0…1: the hold grows it; release within `talk` seconds
        // keeps it open and talking; then it settles.
        let phase: Phase = frame.holding > 0 ? (frame.holding < grow ? .growing : .listening)
                         : (frame.sinceHold < talk ? .talking : .idle)
        let progress: Double = {
            switch phase {
            case .growing: return min(frame.holding / grow, 1)
            case .listening, .talking: return 1
            case .idle: return 0
            }
        }()
        let eased = progress * progress * (3 - 2 * progress)
        LabPhoneCanvas(frame: frame) { size in
            ZStack {
                Color.black.opacity(0.92 * eased)
                    .animation(spring, value: phase)
                LabEdgeGlowStroke(frame: frame, size: size, width: 18, blur: 20,
                                  strength: frame.p("glow", .hold) * eased * (phase == .talking ? 1.2 : 1),
                                  rotate: 0.3, inset: 0)
                VStack {
                    Spacer()
                    TabBarPreview(config: config, selectedTab: .constant(.dashboard), width: size.width - 32)
                        .allowsHitTesting(false)
                        .padding(.bottom, 24)
                        .opacity(1 - eased)
                        .offset(y: 80 * eased)
                }
                // The orb: from the pod to the hero, by the hold.
                let pod = CGFloat(RingConfig.tabBarPodDiameter)
                let podCenter = CGPoint(x: 16 + (size.width - 32) - pod / 2, y: size.height - 24 - pod / 2)
                let heroD = size.width * frame.p("hero", .hold)
                let heroCenter = CGPoint(x: size.width / 2, y: size.height * 0.42)
                let d = pod + (heroD - pod) * eased
                let c = CGPoint(x: podCenter.x + (heroCenter.x - podCenter.x) * eased, y: podCenter.y + (heroCenter.y - podCenter.y) * eased)
                LabHeroView(frame: frame, config: config, diameter: d)
                    .scaleEffect(phase == .talking ? 1 + frame.audio * 0.15 + 0.03 * sin(frame.time * 9) : 1)
                    .position(c)
                    .animation(spring, value: phase)
                VStack(spacing: 10) {
                    Spacer()
                    Text(phase == .talking ? "Speaking" : phase == .listening ? "Listening…" : "Hold to talk")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .contentTransition(.numericText())
                    if phase == .talking {
                        LabCaptionWords(frame: frame, width: size.width - 48, size: 20, style: 1, rate: 4, glow: 0.4, hold: talk)
                            .frame(height: 100)
                    } else {
                        Spacer().frame(height: 100)
                    }
                    Spacer().frame(height: 60)
                }
                .opacity(eased)
            }
        }
    }
}
