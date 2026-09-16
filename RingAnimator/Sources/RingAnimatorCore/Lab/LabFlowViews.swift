import SwiftUI

// The flow labs: what happens when you tap the Nexus tab, on a phone
// canvas with the real app behind it. These are about the whole screen,
// so they draw a phone rather than a disc, and the tappable ones advance
// on a tap — the question is answered by asking it.

// MARK: - Phone canvas

/// The tab bar's place on a phone, matching the main preview's mockup
/// (`PhoneMockupView.screen`): 21 pt in from each side, 21 pt off the
/// bottom. Every flow that draws the bar or puts something in the pod's
/// slot measures from here.
enum LabPhone {
    static let inset: CGFloat = 21
    static let bottom: CGFloat = 21
}

/// A phone-shaped canvas with the demo app's dashboard screenshot behind
/// whatever the flow draws. Sized from the stage's diameter so the Size
/// slider still means something.
struct LabPhoneCanvas<Content: View>: View {
    let frame: LabFrame
    @ViewBuilder let content: (CGSize) -> Content

    /// On a device, the screen itself; otherwise a phone-shaped canvas
    /// sized from the stage's diameter.
    static func size(for frame: LabFrame) -> CGSize {
        if let screen = frame.screen { return screen }
        let w = max(200, frame.diameter * 0.85)
        return CGSize(width: w, height: w * 2.05)
    }

    var body: some View {
        let size = Self.size(for: frame)
        let onDevice = frame.screen != nil
        let corner = onDevice ? AnimationExporter.phoneScreenCornerRadius : size.width * 0.13
        ZStack {
            LabPhoneBackdrop(frame: frame, tab: .dashboard, size: size)
            content(size)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
            .strokeBorder(Color.white.opacity(onDevice ? 0 : (frame.darkStage ? 0.12 : 0.35)), lineWidth: 1))
    }
}

/// What's behind a flow: the app's screenshot for a tab, or — with App
/// UI off — the flat page the main preview shows.
struct LabPhoneBackdrop: View {
    let frame: LabFrame
    let tab: DemoTab
    let size: CGSize

    var body: some View {
        if frame.appUI {
            tab.screenshotImage(dark: frame.darkStage)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            (frame.darkStage ? Color.black : Color(white: 0.96))
                .frame(width: size.width, height: size.height)
        }
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
                    TabBarPreview(config: config, selectedTab: .constant(.dashboard), width: size.width - LabPhone.inset * 2, hidesPodContent: true)
                        .allowsHitTesting(false)
                        .padding(.bottom, LabPhone.bottom)
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
                let verb = [frame.p("orbPod", .journey), frame.p("orbChat", .journey), frame.p("orbVoice", .journey)][stage.rawValue]
                LabHeroView(frame: frame.orbVerb(verb), config: config, diameter: ringFrame.width)
                    .position(x: ringFrame.midX, y: ringFrame.midY)
                    .animation(spring, value: stage)
            }
        }
    }

    private var podCenter: (CGSize) -> CGPoint {
        { size in
            // Mirrors `TabBarPreview`: bar is inset `LabPhone.inset` each side; the
            // pod is the trailing 62pt of it; 24pt above the bottom.
            let pod = CGFloat(RingConfig.tabBarPodDiameter)
            return CGPoint(x: LabPhone.inset + (size.width - LabPhone.inset * 2) - pod / 2, y: size.height - LabPhone.bottom - pod / 2)
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
        let script = LabScript.named(Int(frame.p("script", .journey)))
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
                        bubble(script.ask, mine: true)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        if role == 1 { Spacer().frame(width: 48) }
                        bubble(script.answer, mine: false)
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
    @Environment(\.labNoGlass) private var noGlass

    func body(content: Content) -> some View {
        if noGlass {
            // Harnesses: ImageRenderer drops what is inside a glass
            // effect, so verification renders draw a plain dark panel.
            content.background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(glass, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

/// Set by verification harnesses: draw glass panels flat, because
/// `ImageRenderer` doesn't rasterise Liquid Glass or what sits in it.
public struct LabNoGlassKey: EnvironmentKey { public static let defaultValue = false }
extension EnvironmentValues {
    public var labNoGlass: Bool {
        get { self[LabNoGlassKey.self] }
        set { self[LabNoGlassKey.self] = newValue }
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
                // The hero, in the verb this state maps to (their orb only —
                // any other hero ignores it).
                let verb = [frame.p("orbIdle", .agentStates), frame.p("orbListening", .agentStates),
                            frame.p("orbThinking", .agentStates), frame.p("orbSpeaking", .agentStates)][stage]
                LabHeroView(frame: frame.orbVerb(verb), config: config, diameter: d * 1.3)
                    .scaleEffect(scale)
                    .animation(spring, value: stage)
                // Comet — our own thinking motion, for the ring. Their orb
                // carries its own verb, so it goes without.
                if stage == 2, frame.hero == nil {
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
    @Environment(\.labTextOnDark) private var onDark

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
                            .foregroundStyle(onDark ? Color.white : Color(white: 0.12))
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
                    TabBarPreview(config: config, selectedTab: .constant(.dashboard), width: size.width - LabPhone.inset * 2, hidesPodContent: true)
                        .allowsHitTesting(false)
                        .padding(.bottom, LabPhone.bottom)
                        .opacity(1 - eased)
                        .offset(y: 80 * eased)
                }
                // The orb: from the pod to the hero, by the hold.
                let pod = CGFloat(RingConfig.tabBarPodDiameter)
                let podCenter = CGPoint(x: LabPhone.inset + (size.width - LabPhone.inset * 2) - pod / 2, y: size.height - LabPhone.bottom - pod / 2)
                let heroD = size.width * frame.p("hero", .hold)
                let heroCenter = CGPoint(x: size.width / 2, y: size.height * 0.42)
                let d = pod + (heroD - pod) * eased
                let c = CGPoint(x: podCenter.x + (heroCenter.x - podCenter.x) * eased, y: podCenter.y + (heroCenter.y - podCenter.y) * eased)
                let verb = phase == .talking ? frame.p("orbSpeaking", .hold) : (phase == .idle ? 7 : frame.p("orbListening", .hold))
                LabHeroView(frame: frame.orbVerb(verb), config: config, diameter: d)
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

// MARK: - Gooey (UI) — libraries.dev's Gooey, natively

/// A round + button opening into items with a gooey stretch. The goo is
/// SwiftUI's own Canvas filters — a blur, then an alpha threshold — the
/// same construction as the web's SVG `feGaussianBlur` + `feColorMatrix`.
/// Icons are drawn separately on top so they stay crisp.
struct LabGooeyView: View {
    let frame: LabFrame
    @ObservedObject var config: RingConfig

    private static let icons = ["camera.fill", "photo.fill", "mic.fill", "paperclip", "location.fill", "face.smiling"]

    var body: some View {
        let auto = frame.p("auto", .gooey) >= 0.5
        // Open or closed: taps toggle; auto flips every 3 s.
        let autoOpen = auto && Int(frame.time / 3) % 2 == 1
        let open = (frame.taps % 2 == 1) != autoOpen
        // Time since the last toggle: the tap, or the auto flip.
        let since = min(frame.sinceTap, auto ? frame.time.truncatingRemainder(dividingBy: 3) : .infinity)
        let items = Int(frame.p("items", .gooey))
        LabPhoneCanvas(frame: frame) { size in
            // The pod's centre, exactly where TabBarPreview puts it.
            let pod = CGFloat(RingConfig.tabBarPodDiameter)
            let center = CGPoint(x: LabPhone.inset + (size.width - LabPhone.inset * 2) - pod / 2, y: size.height - LabPhone.bottom - pod / 2)
            ZStack {
                Color.black.opacity(frame.darkStage ? 0.5 : 0.1)
                VStack {
                    Spacer()
                    TabBarPreview(config: config, selectedTab: .constant(.dashboard), width: size.width - LabPhone.inset * 2, hidesPodContent: true)
                        .allowsHitTesting(false)
                        .padding(.bottom, LabPhone.bottom)
                }
                LabGooeyMenu(frame: frame, center: center, open: open, since: since,
                             icons: (0..<items).map { Self.icons[$0 % Self.icons.count] })
                VStack {
                    Spacer()
                    Text("Tap to open")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.bottom, 100)
                }
            }
        }
    }
}

/// The goo itself: the + at `center`, the items coming out of it, drawn
/// from the Gooey knobs in `frame`. Shared by the Gooey lab and the
/// System's play, where the items are the agent's actions.
struct LabGooeyMenu: View {
    let frame: LabFrame
    let center: CGPoint
    let open: Bool
    /// Seconds since it last opened or closed.
    let since: Double
    let icons: [String]
    /// The + itself, or the pod's own look sitting there.
    var drawsButton: Bool = true

    var body: some View {
        let effect = Int(frame.p("effect", .gooey))
        let items = icons.count
        let blur = frame.p("blur", .gooey)
        let contrast = frame.p("contrast", .gooey)
        let waviness = frame.p("waviness", .gooey)
        let spread = frame.p("spread", .gooey)
        let openD = frame.p("openDuration", .gooey) / 1000, closeD = frame.p("closeDuration", .gooey) / 1000
        let openS = frame.p("openStagger", .gooey) / 1000, closeS = frame.p("closeStagger", .gooey) / 1000
        let antic = frame.p("anticipation", .gooey), anticD = frame.p("anticipationDuration", .gooey) / 1000
        let iconFade = frame.p("iconFade", .gooey) / 1000, iconDelay = frame.p("iconDelay", .gooey) / 1000
        let fill: Color = {
            switch Int(frame.p("fill", .gooey)) {
            case 1: return Color(white: 0.92)
            case 2: return Color(hex: "#5AC8FA")
            case 3: return Color(hex: "#FFCF9E")
            case 4: return frame.colors.first ?? .white
            default: return Color(white: 0.13)
            }
        }()
        let iconColor: Color = Int(frame.p("fill", .gooey)) == 0 ? .white : Color(white: 0.1)
        let R: CGFloat = 26
        let travel = 64.0 * spread

        // Per-item progress 0…1 with stagger, eased, plus the anticipation
        // (a pull the other way before the move).
        func progress(_ i: Int) -> Double {
            let d = open ? openD : closeD
            let s = open ? openS : closeS
            let t = max(0, since - Double(i) * s)
            let raw = min(1, t / max(d, 0.01))
            let eased = 1 - pow(1 - raw, 3)
            return open ? eased : 1 - eased
        }
        func anticipationOffset(_ i: Int) -> Double {
            guard open, antic > 0 else { return 0 }
            let t = max(0, since - Double(i) * openS)
            guard t < anticD else { return 0 }
            let u = t / anticD
            return -antic * sin(u * .pi)
        }
        // The + lives in the Nexus tab's slot, so everything comes out to
        // the left along the bar, or up and to the left — never off the
        // screen (Chris, 2026-09-15).
        func position(_ i: Int, _ p: Double) -> (CGPoint, CGSize) {
            let dist = travel * p + anticipationOffset(i)
            let n = Double(i + 1)
            switch effect {
            case 1: // Move: a row to the left along the bar.
                return (CGPoint(x: center.x - dist * n * 0.95, y: center.y), CGSize(width: R * 2, height: R * 2))
            case 2: // Bend: an arc from straight up, curving left as it goes.
                let a = .pi / 2 + Double(i) * 0.5 * p + 0.15
                let reach = dist * (0.8 + 0.5 * n)
                return (CGPoint(x: center.x - cos(a) * reach, y: center.y - sin(a) * reach), CGSize(width: R * 2, height: R * 2))
            case 3: // Melt: oozes left along the bar, stretching as it goes.
                return (CGPoint(x: center.x - dist * n * 0.85, y: center.y),
                        CGSize(width: R * 2 * (1 + 0.5 * p * (1 - p) * 4), height: R * 2 * (1 - 0.2 * p)))
            default: // Morph: a fan up-left, growing from nothing.
                let a = .pi / 2 + (Double(i) + 0.5) / Double(max(items, 1)) * (.pi / 2)
                let reach = dist * 1.1
                return (CGPoint(x: center.x - cos(a) * reach, y: center.y - sin(a) * reach),
                        CGSize(width: R * 2 * (0.3 + 0.7 * p), height: R * 2 * (0.3 + 0.7 * p)))
            }
        }
        // Nothing to draw once it has fully closed — so a pod look under
        // it isn't covered by the goo's own disc.
        let settled = !open && since > closeD + Double(items) * closeS + 0.1
        return ZStack {
            if drawsButton || !settled {
                Canvas { ctx, _ in
                    // The goo: everything drawn in this layer is blurred, then
                    // thresholded, so nearby shapes bridge.
                    ctx.addFilter(.alphaThreshold(min: 0.5, max: 1, color: fill))
                    ctx.addFilter(.blur(radius: blur * (contrast / 18)))
                    ctx.drawLayer { layer in
                        let wob = waviness * sin(frame.time * 6)
                        layer.fill(Path(ellipseIn: CGRect(x: center.x - R - wob, y: center.y - R, width: R * 2 + wob * 2, height: R * 2)), with: .color(fill))
                        for i in 0..<items {
                            let p = progress(i)
                            guard p > 0.001 else { continue }
                            let (pt, sz) = position(i, p)
                            layer.fill(Path(ellipseIn: CGRect(x: pt.x - sz.width / 2, y: pt.y - sz.height / 2, width: sz.width, height: sz.height)), with: .color(fill))
                        }
                    }
                }
            }
            // Icons, crisp, on top: the + rotates to × as it opens.
            if drawsButton {
                let mainP = progress(0)
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .rotationEffect(.degrees(45 * mainP))
                    .position(center)
            }
            ForEach(0..<items, id: \.self) { i in
                let p = progress(i)
                let (pt, _) = position(i, p)
                let t = max(0, since - Double(i) * openS - iconDelay)
                let iconAlpha = open ? min(1, t / max(iconFade, 0.01)) : max(0, 1 - since / max(iconFade, 0.01))
                Image(systemName: icons[i])
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .opacity(iconAlpha * (p > 0.6 ? 1 : 0))
                    .position(pt)
            }
        }
    }
}

// MARK: - Metal (UI) — libraries.dev's Metal v2, natively

struct LabMetalView: View {
    let frame: LabFrame
    @ObservedObject var config: RingConfig

    var body: some View {
        let type = Int(frame.p("type", .metal))
        let preset = Float(frame.p("color", .metal))
        let ringW = frame.p("ring", .metal)
        let optGlow = frame.p("optGlow", .metal) >= 0.5, optRefl = frame.p("optReflection", .metal) >= 0.5
        let optShadow = frame.p("optShadow", .metal) >= 0.5, optBend = frame.p("optBend", .metal) >= 0.5
        let footprint: CGSize = {
            switch type {
            case 1: return CGSize(width: 180, height: 52)
            case 2: return CGSize(width: 220, height: 44)
            case 3: return CGSize(width: 96, height: 30)
            default: return CGSize(width: 56, height: 56)
            }
        }()
        let shapeKind: Float = type == 0 ? 0 : (type == 3 ? 1 : (type == 1 ? 1 : 2))
        let lab = PerceptualGradient.labTriples(frame.colors)
        // Pointer, in the control's own points. Hover is felt within the
        // control's footprint plus the bend reach.
        let local: CGPoint? = frame.pointer.map { CGPoint(x: $0.x + footprint.width / 2, y: $0.y + footprint.height / 2) }
        let hovering = local.map { p in
            p.x > -40 && p.y > -40 && p.x < footprint.width + 40 && p.y < footprint.height + 40
        } ?? false
        let pointerArg = local ?? CGPoint(x: -1, y: -1)
        let glowOn = optGlow && hovering
        ZStack {
            // The glow: the palette, soft, under the control, on hover.
            RoundedRectangle(cornerRadius: shapeKind == 0 ? footprint.width / 2 : (shapeKind == 1 ? footprint.height / 2 : footprint.height * 0.45), style: .continuous)
                .fill(AngularGradient(colors: PerceptualGradient.closedSweep(through: frame.colors.map(PerceptualGradient.rgb), count: 24), center: .center, angle: .degrees(frame.time * 30)))
                .frame(width: footprint.width, height: footprint.height)
                .blur(radius: 14)
                .opacity(glowOn ? 0.35 * frame.p("glow", .metal) : 0)
                .animation(.easeOut(duration: frame.p(glowOn ? "appear" : "disappear", .metal) / 1000), value: glowOn)
            // The control itself.
            controlBody(type: type, footprint: footprint)
            // The ring, the inner shadow, the reflection.
            // Not `.clear`: a view with nothing in it gives colorEffect
            // nothing to rasterise and the ring never draws. 1% alpha is
            // invisible and enough.
            Rectangle()
                .fill(Color.white.opacity(0.01))
                .frame(width: footprint.width, height: footprint.height)
                .colorEffect(ShaderLibrary.bundle(.module).labMetal(
                    .float2(footprint), .float(Float(frame.time)), .float(shapeKind), .float(Float(ringW)),
                    .float(preset), .float(Float(frame.p("strength", .metal))), .float(Float(frame.p("scale", .metal))),
                    .float(Float(optShadow ? frame.p("innerShadow", .metal) : 0)),
                    .float2(optRefl ? pointerArg : CGPoint(x: -1, y: -1)),
                    .float(Float(frame.p("rReach", .metal) / 10)), .float(Float(frame.p("rDistance", .metal))),
                    .float(Float(frame.p("rFalloff", .metal))), .float(Float(frame.p("rSpecular", .metal))),
                    .floatArray(lab)))
        }
        .frame(width: footprint.width + 80, height: footprint.height + 80)
        .visualEffect { content, proxy in
            // The dent: the whole control bends toward the pointer.
            let p = local.map { CGPoint(x: $0.x + 40, y: $0.y + 40) } ?? CGPoint(x: -1, y: -1)
            return content.distortionEffect(
                ShaderLibrary.bundle(.module).labDent(.float2(optBend ? p : CGPoint(x: -1, y: -1)),
                                                       .float(Float(frame.p("reach", .metal))),
                                                       .float(Float(frame.p("dent", .metal) * frame.p("bend", .metal)))),
                maxSampleOffset: CGSize(width: 30, height: 30))
        }
    }

    @ViewBuilder
    private func controlBody(type: Int, footprint: CGSize) -> some View {
        let dark = frame.darkStage
        let bg = dark ? Color(white: 0.1) : Color(white: 0.97)
        let fg = dark ? Color.white : Color.black
        switch type {
        case 1:
            Text("Continue")
                .font(.headline).foregroundStyle(fg)
                .frame(width: footprint.width, height: footprint.height)
                .background(Capsule().fill(bg))
        case 2:
            Text("Nexus")
                .font(.system(size: 28, weight: .bold)).foregroundStyle(fg)
                .frame(width: footprint.width, height: footprint.height)
        case 3:
            Text("NEW")
                .font(.caption.weight(.bold)).foregroundStyle(fg)
                .frame(width: footprint.width, height: footprint.height)
                .background(Capsule().fill(bg))
        default:
            Image(systemName: "arrow.up")
                .font(.system(size: 20, weight: .semibold)).foregroundStyle(fg)
                .frame(width: footprint.width, height: footprint.height)
                .background(Circle().fill(bg))
        }
    }
}
