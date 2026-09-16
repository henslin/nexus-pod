import SwiftUI
import BorderBeamKit

/// Liquid Glass morphing: one glass shape stepping through a list of
/// states — pod, pill, card, sheet, full screen — with content riding
/// inside, and per-state adornments (edge glow, waveform, caption).
///
/// This is the pod-to-sheet expansion Chris described (2026-09-14: "the
/// animation might start in the tab circle but expand into a sheet or
/// even full screen"), as the platform does it: the same glass view, its
/// frame and corner radius animated on a spring. Liquid Glass re-renders
/// its refraction and highlights for the shape at every frame of the
/// animation, which is what makes it read as one object growing rather
/// than one view being replaced by another.
///
/// 2026-09-15: the UI room narrowed to this. The states became a list
/// (`LabState.morphStates`) you add to and remove from, and the pieces
/// of the other UI labs became things a state can *carry* — so "edge
/// glow on the sheet but not the pill" is a checkbox, not a new lab.
/// `LabMorphStage` (below) is the workbench: the hero animating on top,
/// every state on its own underneath.
struct LabMorphView: View {
    let frame: LabFrame
    @ObservedObject var config: RingConfig

    /// The current state's index: hold seconds per state, ping-pong or
    /// round, plus taps.
    private var index: Int {
        let states = frame.morphStates
        guard states.count > 1 else { return 0 }
        let hold = max(frame.p("hold", .morph), 0.2)
        let step = Int(frame.time / hold) + frame.taps
        if frame.p("pingpong", .morph) >= 0.5 {
            let period = (states.count - 1) * 2
            let k = step % period
            return k < states.count ? k : period - k
        }
        return step % states.count
    }

    /// The phone the states live in. Real points: the panels are real
    /// iOS sizes, so the canvas is a real phone.
    static let phone = CGSize(width: 393, height: 780)

    /// Where a kind of panel sits on the phone: the pod in the tab bar's
    /// trailing slot, the pill and card just above the bar, the sheet
    /// and full screen from the bottom.
    static func home(of kind: LabMorphKind) -> CGPoint {
        let phone = Self.phone
        let size = LabMorphPanel.size(of: kind)
        let pod = CGFloat(RingConfig.tabBarPodDiameter)
        switch kind {
        case .pod:        return CGPoint(x: 16 + (phone.width - 32) - pod / 2, y: phone.height - 24 - pod / 2)
        case .pill, .card: return CGPoint(x: phone.width / 2, y: phone.height - 24 - 62 - 12 - size.height / 2)
        case .sheet:      return CGPoint(x: phone.width / 2, y: phone.height - size.height / 2)
        case .fullScreen: return CGPoint(x: phone.width / 2, y: phone.height / 2)
        }
    }

    var body: some View {
        let states = frame.morphStates
        let state = states.isEmpty ? LabMorphState(.pod) : states[min(index, states.count - 1)]
        let spring = Animation.spring(response: frame.p("spring", .morph),
                                      dampingFraction: 1 - frame.p("bounce", .morph) * 0.45)
        // Where we are within this state's hold — the transitions run
        // off it. Deterministic, like everything else on the clock.
        let hold = max(frame.p("hold", .morph), 0.2)
        let sinceChange = frame.time.truncatingRemainder(dividingBy: hold)
        let phone = Self.phone
        // The panel animates between homes as it morphs, so it grows
        // *out of* the pod rather than in place.
        let center = Self.home(of: state.kind)
        ZStack {
            DemoTab.dashboard.screenshotImage(dark: frame.darkStage)
                .resizable().scaledToFill()
                .frame(width: phone.width, height: phone.height)
                .clipped()
            Color.black.opacity(state.kind == .sheet ? 0.4 : state.kind == .fullScreen ? 0.85 : 0)
                .animation(spring, value: state.id)
            VStack {
                Spacer()
                TabBarPreview(config: config, selectedTab: .constant(.dashboard), width: phone.width - 32, hidesPodContent: true)
                    .allowsHitTesting(false)
                    .padding(.bottom, 24)
                    .opacity(state.kind == .fullScreen ? 0 : 1)
                    .animation(spring, value: state.id)
            }
            LabMorphPanel(state: state, frame: frame, config: config,
                          sinceChange: sinceChange, untilChange: hold - sinceChange)
                .position(center)
                .animation(spring, value: state.id)
        }
        .frame(width: phone.width, height: phone.height)
        .clipShape(RoundedRectangle(cornerRadius: 50, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 50, style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
    }
}

/// One state as a glass panel: the shape its kind takes, the content it
/// carries, and its adornments. Drawn by the hero (animated between
/// states) and by the workbench (one per state, still).
public struct LabMorphPanel: View {
    let state: LabMorphState
    let frame: LabFrame
    @ObservedObject var config: RingConfig
    /// Seconds since this state became current, and until it stops
    /// being — the transitions' clock. Infinity for a still card.
    var sinceChange: Double = .infinity
    var untilChange: Double = .infinity
    /// What the surface says — the agent's state, in play. `nil` shows
    /// the workbench's sample copy.
    var caption: String? = nil
    /// A conversation to lay out instead of the sample copy — Q Branch's
    /// play, running a script through the states.
    var conversation: LabConversation? = nil

    public init(state: LabMorphState, frame: LabFrame, config: RingConfig, sinceChange: Double = .infinity, untilChange: Double = .infinity, caption: String? = nil, conversation: LabConversation? = nil) {
        self.state = state
        self.frame = frame
        self.config = config
        self.sinceChange = sinceChange
        self.untilChange = untilChange
        self.caption = caption
        self.conversation = conversation
    }

    /// 0 → 1 as the content arrives, 1 → 0 as it leaves.
    private var envelope: Double {
        let tin = max(frame.p("transIn", .morph), 0.05)
        let tout = max(frame.p("transOut", .morph), 0.05)
        let arriving = state.enter == .none ? 1 : min(1, sinceChange / tin)
        let leaving = state.exit == .none ? 1 : min(1, untilChange / tout)
        let e = min(arriving, leaving)
        return e * e * (3 - 2 * e)
    }

    /// The glow's extra brightness on a flare entrance, decaying.
    private var flare: Double {
        guard state.enter == .flare, sinceChange.isFinite else { return 0 }
        let tin = max(frame.p("transIn", .morph), 0.05)
        return max(0, 1 - sinceChange / (tin * 2)) * 1.5
    }

    /// Content offset/scale for grow and slide, from the envelope.
    private var contentScale: CGFloat {
        let leavingGrow = state.exit == .grow, enteringGrow = state.enter == .grow
        guard enteringGrow || leavingGrow else { return 1 }
        return CGFloat(0.6 + 0.4 * envelope)
    }
    private var contentOffset: CGFloat {
        let slide = state.enter == .slide || state.exit == .slide
        guard slide else { return 0 }
        return CGFloat((1 - envelope) * 28)
    }

    /// Real iOS sizes, in points, on a 393-wide phone: the pod is the tab
    /// bar's; the pill is the tab bar accessory's width; the card is a
    /// notification's; the sheet a medium detent; full screen the screen.
    public static func size(of kind: LabMorphKind) -> CGSize {
        switch kind {
        case .pod:        return CGSize(width: 62, height: 62)
        case .pill:       return CGSize(width: 361, height: 62)
        case .card:       return CGSize(width: 361, height: 176)
        case .sheet:      return CGSize(width: 393, height: 560)
        case .fullScreen: return LabMorphView.phone
        }
    }
    private var size: CGSize { Self.size(of: state.kind) }

    private var cornerRadius: CGFloat {
        switch state.kind {
        case .pod, .pill: return 31
        case .card:       return 28
        case .sheet:      return 38
        case .fullScreen: return 50
        }
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let env = envelope
        ZStack {
            content
                .opacity(state.enter == .none && state.exit == .none ? 1 : env)
                .scaleEffect(contentScale)
                .offset(y: contentOffset)
        }
        .frame(width: size.width, height: size.height)
        // Everything the state carries is clipped to the state's own
        // shape — captions, waveforms, the glow. Nothing spills.
        .clipShape(shape)
        .modifier(LabGlassShape(cornerRadius: cornerRadius, glass: config.glass))
        // Their beam wraps the glass: it draws outside the shape by
        // design (the bloom), reading the Border Beam · Kit knobs.
        .modifier(LabBeamWrap(enabled: state.adornments.contains(.borderBeam), frame: frame, cornerRadius: cornerRadius, envelope: env))
        .background {
            // Edge glow *inside* the container's edge, clipped by it — the
            // iOS 18 Siri construction — and under the glass so the glass
            // refracts it. It arrives and leaves with the content, and a
            // flare entrance overshoots then settles.
            if state.adornments.contains(.edgeGlow) {
                LabEdgeGlowAdornment(frame: frame, shape: shape, size: size, envelope: env, flare: flare)
                    .clipShape(shape)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let conversation {
            LabConversationView(kind: state.kind, conversation: conversation, frame: frame, config: config, size: size)
        } else {
            sample
        }
    }

    @ViewBuilder
    private var sample: some View {
        let hasWave = state.adornments.contains(.waveform)
        let hasCaption = state.adornments.contains(.caption)
        let hasTranscript = state.adornments.contains(.transcript)
        switch state.kind {
        case .pod:
            LabHeroView(frame: frame, config: config, diameter: 62)
        case .pill:
            HStack(spacing: 10) {
                LabHeroView(frame: frame, config: config, diameter: 44)
                if hasWave {
                    LabWaveformBars(frame: frame, bars: 20, height: 22).frame(height: 44)
                } else {
                    Text(caption ?? (hasCaption ? "Listening…" : "John arrived home."))
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 12)
        case .card:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    LabHeroView(frame: frame, config: config, diameter: 44)
                    Text(caption ?? "John arrived home.")
                        .font(.headline)
                    Spacer(minLength: 0)
                }
                if hasCaption {
                    LabCaptionWords(frame: frame, width: size.width - 32, size: 15, style: 1, rate: 5, glow: 0.3, hold: 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Front door unlocked at 5:42 PM. Living room lights are on.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if hasWave { LabWaveformBars(frame: frame, bars: 28, height: 18).frame(height: 24) }
            }
            .padding(16)
        case .sheet:
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    LabHeroView(frame: frame, config: config, diameter: 56)
                    Text(caption ?? "Nexus")
                        .font(.title2.bold())
                    Spacer(minLength: 0)
                }
                if hasTranscript {
                    LabTranscriptView(frame: frame, width: size.width - 40, size: 17, glow: 0.35)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if hasCaption {
                    LabCaptionWords(frame: frame, width: size.width - 40, size: 17, style: 1, rate: 4, glow: 0.35, hold: 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("John arrived home.")
                        .font(.headline)
                    Text("Front door unlocked at 5:42 PM. Living room lights are on. The thermostat is holding 70°.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Group {
                        if hasWave { LabWaveformBars(frame: frame, bars: 26, height: 20) }
                        else { Text("Message").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14) }
                    }
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(.fill.tertiary))
                    LabHeroView(frame: frame, config: config, diameter: 44)
                }
            }
            .padding(20)
        case .fullScreen:
            VStack(spacing: 14) {
                Spacer()
                LabHeroView(frame: frame, config: config, diameter: size.width * 0.5)
                Text(caption ?? "Listening…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                if hasCaption {
                    LabCaptionWords(frame: frame, width: size.width - 48, size: 20, style: 1, rate: 4, glow: 0.4, hold: 4)
                        .frame(height: 120)
                }
                if hasWave { LabWaveformBars(frame: frame, bars: 32, height: 24).frame(height: 30).padding(.horizontal, 24) }
                Spacer()
                if hasTranscript {
                    LabTranscriptView(frame: frame, width: size.width - 48, size: 20, glow: 0.4)
                        .frame(height: 120)
                        .padding(.bottom, 40)
                }
            }
        }
    }
}

/// The Morph workbench: the hero animating through the states on top,
/// and every state on its own underneath — with its adornments, a menu
/// to add or remove them, and a way to add states.
struct LabMorphStage: View {
    @ObservedObject var lab: LabState
    @ObservedObject var config: RingConfig
    let frame: LabFrame

    var body: some View {
        // The hero is a real phone, scaled so its height is ~1.9× the
        // stage's diameter — the Size slider still means something.
        let heroScale = frame.diameter * 1.9 / LabMorphView.phone.height
        VStack(spacing: 18) {
            LabMorphView(frame: frame, config: config)
                .scaleEffect(heroScale)
                .frame(width: LabMorphView.phone.width * heroScale, height: LabMorphView.phone.height * heroScale)

            Divider().frame(maxWidth: 600)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(Array(lab.morphStates.enumerated()), id: \.element.id) { i, state in
                        stateCard(state, index: i)
                    }
                    addCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity)

            // All-states switches.
            HStack(spacing: 14) {
                ForEach(LabMorphAdornment.allCases) { adornment in
                    let all = !lab.morphStates.isEmpty && lab.morphStates.allSatisfy { $0.adornments.contains(adornment) }
                    Button {
                        lab.setAll(adornment, on: !all)
                    } label: {
                        Label(all ? "\(adornment.label) off all" : "\(adornment.label) on all", systemImage: adornment.symbol)
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
                Menu {
                    Section("All enter with") {
                        ForEach(LabMorphTransition.allCases) { t in Button(t.label) { lab.setAllTransitions(enter: t, exit: nil) } }
                    }
                    Section("All leave with") {
                        ForEach(LabMorphTransition.allCases.filter { $0 != .flare }) { t in Button(t.label) { lab.setAllTransitions(enter: nil, exit: t) } }
                    }
                } label: {
                    Label("Transitions", systemImage: "arrow.left.arrow.right").font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    /// One state, still, at its true size scaled as a whole to fit the
    /// card — so type and spacing are the real thing, only smaller.
    private func stateCard(_ state: LabMorphState, index: Int) -> some View {
        let cardDiameter: CGFloat = 220
        let real = LabMorphPanel.size(of: state.kind)
        let scale = min(cardDiameter / real.width, cardDiameter / real.height, 1)
        return VStack(spacing: 8) {
            LabMorphPanel(state: state, frame: frame, config: config)
                .scaleEffect(scale)
                .frame(width: cardDiameter, height: cardDiameter)
            HStack(spacing: 6) {
                Text("\(index + 1) · \(state.kind.label)")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Menu {
                    Section("Carries") {
                        ForEach(LabMorphAdornment.allCases) { adornment in
                            Button {
                                lab.toggle(adornment, on: state.id)
                            } label: {
                                Label(adornment.label, systemImage: state.adornments.contains(adornment) ? "checkmark" : adornment.symbol)
                            }
                        }
                    }
                    Section("Enters") {
                        ForEach(LabMorphTransition.allCases) { t in
                            Button { lab.setEnter(t, on: state.id) } label: {
                                Label(t.label, systemImage: state.enter == t ? "checkmark" : "arrow.down.right")
                            }
                        }
                    }
                    Section("Leaves") {
                        ForEach(LabMorphTransition.allCases.filter { $0 != .flare }) { t in
                            Button { lab.setExit(t, on: state.id) } label: {
                                Label(t.label, systemImage: state.exit == t ? "checkmark" : "arrow.up.left")
                            }
                        }
                    }
                    Section("Shape") {
                        ForEach(LabMorphKind.allCases) { kind in
                            Button(kind.label) {
                                if let i = lab.morphStates.firstIndex(where: { $0.id == state.id }) { lab.morphStates[i].kind = kind }
                            }
                        }
                    }
                    // Into the System: this state, with the Morph knobs,
                    // as what an action opens.
                    Section("Use as surface for") {
                        ForEach(LabActionItem.allCases) { item in
                            Button { lab.useMorphState(state, for: item) } label: {
                                Label(item.label, systemImage: lab.spec.surface(for: item)?.kind == state.kind ? "checkmark" : item.symbol)
                            }
                        }
                    }
                    Button("Remove State", role: .destructive) { lab.removeMorphState(state.id) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .frame(width: cardDiameter)
            // What it carries, and how it comes and goes, as chips.
            HStack(spacing: 4) {
                ForEach(LabMorphAdornment.allCases.filter { state.adornments.contains($0) }) { a in
                    Label(a.label, systemImage: a.symbol)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.fill.tertiary))
                }
                Text("\(state.enter.label) → \(state.exit.label)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .frame(width: cardDiameter)
        }
    }

    private var addCard: some View {
        Menu {
            ForEach(LabMorphKind.allCases) { kind in
                Button(kind.label) { lab.addMorphState(kind) }
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus.circle").font(.system(size: 28))
                Text("Add State").font(.caption)
            }
            .frame(width: 120, height: 200)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(.tertiary))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

/// The edge glow a state carries: a palette band inside the container's
/// edge, and/or a tracer — a bright head running round the perimeter
/// with a fading trail — both under the glass, both breathing.
struct LabEdgeGlowAdornment: View {
    let frame: LabFrame
    let shape: RoundedRectangle
    let size: CGSize
    let envelope: Double
    let flare: Double

    var body: some View {
        let style = Int(frame.p("glowStyle", .morph))
        let width = frame.p("glowWidth", .morph), blur = frame.p("glowBlur", .morph)
        let inset = frame.p("glowInset", .morph)
        let spin = frame.p("glowSpin", .morph)
        let pulse = 1 - frame.p("glowPulse", .morph) * 0.5 * (0.5 + 0.5 * sin(frame.time * 1.5))
        let single = frame.p("glowColor", .morph) >= 0.5
        let primary = frame.colors.first ?? .white
        let sweep = PerceptualGradient.closedSweep(through: frame.colors.map(PerceptualGradient.rgb), count: 48)
        let paint: AnyShapeStyle = single
            ? AnyShapeStyle(primary)
            : AnyShapeStyle(AngularGradient(colors: sweep, center: .center, angle: .degrees(frame.time * spin * 60)))
        let strength = min(1.6, (0.8 + frame.audio * 0.4) * envelope * pulse + flare)
        ZStack {
            if style == 0 || style == 2 {
                shape.strokeBorder(paint, lineWidth: width)
                    .padding(inset)
                    .blur(radius: blur)
                shape.strokeBorder(paint, lineWidth: 2)
                    .padding(inset)
                    .opacity(0.8)
            }
            if style >= 1 {
                tracers(paint: paint, inset: inset)
            }
        }
        .opacity(strength)
        .blendMode(.plusLighter)
    }

    /// Tracers: `trim` on the container's own path, so the head follows
    /// the corners exactly. The trail is the same trim drawn a few times
    /// with shrinking length and opacity — a cheap gradient along a path.
    private func tracers(paint: AnyShapeStyle, inset: Double) -> some View {
        let count = Int(frame.p("tracers", .morph))
        let speed = frame.p("tracerSpeed", .morph)
        let trail = frame.p("tracerTrail", .morph)
        let lineWidth = frame.p("tracerWidth", .morph)
        let glow = frame.p("tracerGlow", .morph)
        let head = (frame.time * speed * 0.25).truncatingRemainder(dividingBy: 1)
        let insetShape = RoundedRectangle(cornerRadius: max(shape.cornerSize.width - inset, 4), style: .continuous)
        return ZStack {
            ForEach(0..<count, id: \.self) { k in
                let h = (head + Double(k) / Double(count)).truncatingRemainder(dividingBy: 1)
                ForEach(0..<5, id: \.self) { seg in
                    let f = Double(seg) / 5
                    let from = h - trail * (1 - f)
                    let opacity = 0.18 + 0.82 * f
                    let w = lineWidth * (0.4 + 0.6 * f)
                    // The path is in the panel's own coordinates, inset by
                    // hand — padding a Path view would shift its origin.
                    let margin = inset + lineWidth
                    trimmed(insetShape, from: from, to: h, margin: margin)
                        .stroke(paint, style: StrokeStyle(lineWidth: w, lineCap: .round))
                        .opacity(opacity)
                    trimmed(insetShape, from: from, to: h, margin: margin)
                        .stroke(paint, style: StrokeStyle(lineWidth: w * 4, lineCap: .round))
                        .blur(radius: 6)
                        .opacity(opacity * 0.6 * glow)
                }
            }
        }
    }

    /// `trim` that wraps past 1 and below 0, so a trail crossing the
    /// path's start draws as two pieces instead of vanishing.
    private func trimmed(_ shape: RoundedRectangle, from: Double, to: Double, margin: Double) -> Path {
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: margin, dy: margin)
        let base = shape.path(in: rect)
        if from >= 0 {
            return base.trimmedPath(from: from, to: to)
        }
        var p = base.trimmedPath(from: from + 1, to: 1)
        p.addPath(base.trimmedPath(from: 0, to: to))
        return p
    }
}

/// Libraries.dev's Border beam round a Morph state, when it carries one.
private struct LabBeamWrap: ViewModifier {
    let enabled: Bool
    let frame: LabFrame
    let cornerRadius: CGFloat
    let envelope: Double

    func body(content: Content) -> some View {
        if enabled {
            let s = LabBeamSettings(frame: frame)
            BorderBeam(size: s.size, colorVariant: s.variant, theme: s.theme, duration: s.duration,
                       borderRadius: cornerRadius, brightness: s.brightness, saturation: s.saturation,
                       hueRange: s.hueRange, strength: s.strength * envelope, tuning: s.tuning) {
                content
            }
        } else {
            content
        }
    }
}
