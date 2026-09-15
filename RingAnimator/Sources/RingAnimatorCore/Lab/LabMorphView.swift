import SwiftUI

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

    var body: some View {
        let states = frame.morphStates
        let state = states.isEmpty ? LabMorphState(.pod) : states[min(index, states.count - 1)]
        let spring = Animation.spring(response: frame.p("spring", .morph),
                                      dampingFraction: 1 - frame.p("bounce", .morph) * 0.45)
        LabMorphPanel(state: state, frame: frame, config: config, diameter: frame.diameter)
            .animation(spring, value: state.id)
            .frame(width: frame.diameter, height: frame.diameter)
    }
}

/// One state as a glass panel: the shape its kind takes, the content it
/// carries, and its adornments. Drawn by the hero (animated between
/// states) and by the workbench (one per state, still).
struct LabMorphPanel: View {
    let state: LabMorphState
    let frame: LabFrame
    @ObservedObject var config: RingConfig
    let diameter: CGFloat

    private var size: CGSize {
        let d = diameter
        switch state.kind {
        case .pod:        return CGSize(width: 62, height: 62)
        case .pill:       return CGSize(width: min(d * 0.9, 300), height: 62)
        case .card:       return CGSize(width: min(d * 0.9, 320), height: 170)
        case .sheet:      return CGSize(width: d, height: d * 0.95)
        case .fullScreen: return CGSize(width: d, height: d)
        }
    }

    private var cornerRadius: CGFloat {
        switch state.kind {
        case .pod, .pill: return 31
        case .card:       return 28
        case .sheet:      return 36
        case .fullScreen: return diameter * 0.12
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            content
        }
        .frame(width: size.width, height: size.height)
        .modifier(LabGlassShape(cornerRadius: cornerRadius, glass: config.glass))
        .background {
            // Edge glow sits *under* the glass so the glass refracts it —
            // the same construction as Button Glow.
            if state.adornments.contains(.edgeGlow) {
                let sweep = PerceptualGradient.closedSweep(through: frame.colors.map(PerceptualGradient.rgb), count: 48)
                let width = frame.p("glowWidth", .morph), blur = frame.p("glowBlur", .morph)
                shape.strokeBorder(AngularGradient(colors: sweep, center: .center, angle: .degrees(frame.time * 40)), lineWidth: width)
                    .padding(-width * 0.5)
                    .blur(radius: blur)
                    .opacity(0.8 + frame.audio * 0.4)
                    .blendMode(.plusLighter)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let hasWave = state.adornments.contains(.waveform)
        let hasCaption = state.adornments.contains(.caption)
        switch state.kind {
        case .pod:
            LabHeroView(frame: frame, config: config, diameter: 62)
        case .pill:
            HStack(spacing: 10) {
                LabHeroView(frame: frame, config: config, diameter: 44)
                if hasWave {
                    LabWaveformBars(frame: frame, bars: 20, height: 22).frame(height: 44)
                } else {
                    Text(hasCaption ? "Listening…" : "John arrived home.")
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 12)
        case .card:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    LabHeroView(frame: frame, config: config, diameter: 44)
                    Text("John arrived home.")
                        .font(.system(size: 17, weight: .semibold))
                    Spacer(minLength: 0)
                }
                if hasCaption {
                    LabCaptionWords(frame: frame, width: size.width - 32, size: 13, style: 1, rate: 5, glow: 0.3, hold: 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Front door unlocked at 5:42 PM. Living room lights are on.")
                        .font(.system(size: 13))
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
                    Text("Nexus")
                        .font(.system(size: 22, weight: .bold))
                    Spacer(minLength: 0)
                }
                if hasCaption {
                    LabCaptionWords(frame: frame, width: size.width - 40, size: 17, style: 1, rate: 4, glow: 0.35, hold: 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("John arrived home.")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Front door unlocked at 5:42 PM. Living room lights are on. The thermostat is holding 70°.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Group {
                        if hasWave { LabWaveformBars(frame: frame, bars: 26, height: 20) }
                        else { Text("Message").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14) }
                    }
                    .frame(height: 40)
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(.fill.tertiary))
                    LabHeroView(frame: frame, config: config, diameter: 40)
                }
            }
            .padding(20)
        case .fullScreen:
            VStack(spacing: 14) {
                Spacer()
                LabHeroView(frame: frame, config: config, diameter: size.width * 0.5)
                Text("Listening…")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                if hasCaption {
                    LabCaptionWords(frame: frame, width: size.width - 48, size: 18, style: 1, rate: 4, glow: 0.4, hold: 4)
                        .frame(height: 90)
                }
                if hasWave { LabWaveformBars(frame: frame, bars: 32, height: 24).frame(height: 30).padding(.horizontal, 24) }
                Spacer()
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
        VStack(spacing: 18) {
            LabMorphView(frame: frame, config: config)
                .frame(width: frame.diameter, height: frame.diameter)

            Divider().frame(maxWidth: frame.diameter * 1.6)

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
            }
        }
    }

    /// One state, still, at a fixed reduced size, with its controls.
    private func stateCard(_ state: LabMorphState, index: Int) -> some View {
        let cardDiameter: CGFloat = 200
        return VStack(spacing: 8) {
            LabMorphPanel(state: state, frame: frame.resized(cardDiameter), config: config, diameter: cardDiameter)
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
                    Section("Shape") {
                        ForEach(LabMorphKind.allCases) { kind in
                            Button(kind.label) {
                                if let i = lab.morphStates.firstIndex(where: { $0.id == state.id }) { lab.morphStates[i].kind = kind }
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
            // What it carries, as chips.
            HStack(spacing: 4) {
                ForEach(LabMorphAdornment.allCases.filter { state.adornments.contains($0) }) { a in
                    Label(a.label, systemImage: a.symbol)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.fill.tertiary))
                }
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
