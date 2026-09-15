import SwiftUI
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// The Lab's stage: the selected experiment, large, on a backdrop, with
/// the shared knobs beside it.
///
/// One clock for every experiment — seconds since the stage appeared,
/// times `speed` — so a Float in a shader never sees wall-clock time (see
/// `RingView.shaderSweep` for the precision collapse that causes). One
/// audio monitor, started only while Audio Reactive is on, so the mic
/// indicator isn't lit for a sandbox nobody is speaking to.
public struct LabStageView: View {
    @ObservedObject var lab: LabState
    @ObservedObject var config: RingConfig
    @StateObject private var audio = AudioSpectrumMonitor()
    @State private var appeared = Date()
    @State private var savedFrameMessage: String?
    /// Which post effect's knobs are open in the panel.
    @State private var openPost: LabPostEffect?

    public init(lab: LabState, config: RingConfig) {
        self.lab = lab
        self.config = config
    }

    public var body: some View {
        HStack(spacing: 0) {
            stage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            controls
                .frame(width: 300)
        }
        .onAppear { appeared = Date() }
        .onChange(of: lab.audioReactive, initial: true) { _, on in
            if on { audio.start() } else { audio.stop() }
        }
        .onChange(of: lab.audioAttack, initial: true) { _, v in audio.attack = v }
        .onChange(of: lab.audioRelease, initial: true) { _, v in audio.release = v }
        .onDisappear { audio.stop() }
    }

    private func colors(at time: Double) -> [Color] {
        lab.colors(config: config, at: time)
    }

    private var bands: LabAudioBands { lab.bands(from: audio) }

    private func frame(at date: Date, diameter: CGFloat) -> LabFrame {
        lab.frame(at: date, since: appeared, diameter: diameter, config: config, audio: audio)
    }

    private var stage: some View {
        ZStack(alignment: .bottomLeading) {
            (lab.darkStage ? Color(white: 0.06) : Color(white: 0.94))
            TimelineView(.animation) { timeline in
                let f = frame(at: timeline.date, diameter: CGFloat(lab.diameter))
                Group {
                    if lab.experiment == .morph {
                        // The workbench: hero on top, every state below.
                        ScrollView(.vertical) {
                            LabMorphStage(lab: lab, config: config, frame: f)
                                .padding(.vertical, 24)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        LabExperimentView(experiment: lab.experiment, frame: f, config: config, post: lab.post)
                    }
                }
                .id(lab.experiment)
                .environment(\.colorScheme, lab.darkStage ? .dark : .light)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                if lab.experiment.isTappable { lab.advance() }
            }
            // Press and hold, for the Hold flow: begins on touch-down,
            // ends on release — `DragGesture(minimumDistance: 0)` is the
            // one gesture that reports both.
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if lab.experiment.isHoldable { lab.beginHold() } }
                .onEnded { _ in lab.endHold() })
            if lab.showPod, !lab.experiment.usesPhoneCanvas {
                podPreview
                    .padding(20)
            }
        }
    }

    /// The same experiment at the pod's size, in the pod's glass, in the
    /// stage's corner. The large stage is where you tune; this is where
    /// it ships, and an effect that only works at 360pt is not a pod.
    private var podPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            TimelineView(.animation) { timeline in
                let pod = CGFloat(RingConfig.tabBarPodDiameter)
                let ring = CGFloat(RingConfig.tabBarRingDiameter)
                // Pod Fill: the whole 62pt, edge to edge. Off: the ring's
                // own proportion inside the pod, for comparison with today.
                let inner = LabExperimentView(experiment: lab.experiment,
                                              frame: frame(at: timeline.date, diameter: lab.podFill ? pod : ring * 1.3),
                                              config: config,
                                              post: lab.post)
                    .frame(width: pod, height: pod)
                    .clipShape(Circle())
                Group {
                    if #available(iOS 26.0, macOS 26.0, *) {
                        inner.glassEffect(config.glass, in: Circle())
                    } else {
                        inner.background(.ultraThinMaterial, in: Circle())
                    }
                }
                .environment(\.colorScheme, lab.darkStage ? .dark : .light)
            }
            Text(lab.podFill ? "Pod · 62pt · filled" : "Pod · 62pt")
                .font(.caption2)
                .foregroundStyle(lab.darkStage ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
        }
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lab.experiment.name).font(.title3.weight(.semibold))
                    Text(lab.experiment.technology)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text(lab.experiment.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()
                sectionTitle("Stage")
                LabSlider(title: "Intensity", value: $lab.intensity, range: 0...1)
                LabSlider(title: "Speed", value: $lab.speed, range: 0.1...3, format: "%.1f×")
                LabSlider(title: "Size", value: $lab.diameter, range: 62...600, format: "%.0f pt")
                LabSlider(title: "Fill", value: $lab.fill, range: 0...1.3,
                          help: "Scales the experiment to fill the circle. 1 is edge to edge; past it crops.")
                Toggle("Dark Stage", isOn: $lab.darkStage)
                Toggle("Pod Preview", isOn: $lab.showPod)
                if lab.showPod {
                    Toggle("Fill Pod", isOn: $lab.podFill)
                        .padding(.leading, 12)
                }
                if lab.experiment.drawsHero {
                    Picker("Hero", selection: $lab.hero) {
                        Text("Ring").tag(LabExperiment?.none)
                        ForEach(LabExperiment.allCases.filter(\.canBeHero)) { e in
                            Text(e.name).tag(LabExperiment?.some(e))
                        }
                    }
                    .pickerStyle(.menu)
                    Text("What this flow draws where the ring goes. Any animation lab, with the post stack.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()
                sectionTitle("Colour")
                Picker("Palette", selection: $lab.palette) {
                    ForEach(LabPalette.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                paletteStrip
                LabSlider(title: "Hue Drift", value: $lab.hueDrift, range: -90...90, format: "%.0f°/s",
                          help: "Rotates every colour's hue over time. The palette's relationships hold.")
                TextField("Glyph (SF Symbol)", text: $lab.glyph)
                Text("Drawn inside. Orb, Refraction, Liquid and Sphere are the ones built for it.")
                    .font(.caption2).foregroundStyle(.tertiary)

                Divider()
                sectionTitle("Audio")
                Toggle("Audio Reactive", isOn: $lab.audioReactive)
                if lab.audioReactive {
                    Picker("Drives", selection: $lab.audioSource) {
                        ForEach(LabAudioSource.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    LabSlider(title: "Sensitivity", value: $lab.audioSensitivity, range: 0.5...5, format: "%.1f×")
                    LabSlider(title: "Attack", value: $lab.audioAttack, range: 0.005...0.3, format: "%.3f s",
                              help: "How fast a rise is followed.")
                    LabSlider(title: "Release", value: $lab.audioRelease, range: 0.05...2, format: "%.2f s",
                              help: "How slowly a fall is followed. Long release is the ‘breathing’ look.")
                    let b = bands
                    LabBandMeters(bands: b)
                }

                Divider()
                sectionTitle("Post Effects")
                Text("Stacked over the experiment, in this order. Each uses its own knobs below.")
                    .font(.caption2).foregroundStyle(.tertiary)
                ForEach(LabPostEffect.allCases) { effect in
                    let on = lab.post.contains(effect)
                    HStack {
                        Toggle(effect.experiment.name, isOn: Binding(
                            get: { on }, set: { _ in lab.togglePost(effect) }))
                        Spacer()
                        if on {
                            Button {
                                openPost = openPost == effect ? nil : effect
                            } label: {
                                Image(systemName: openPost == effect ? "chevron.up" : "slider.horizontal.3")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    if on, openPost == effect {
                        knobs(for: effect.experiment)
                            .padding(.leading, 12)
                    }
                }

                if !lab.experiment.parameters.isEmpty {
                    Divider()
                    HStack {
                        sectionTitle(lab.experiment.name)
                        Spacer()
                        Button("Reset") { lab.resetParameters(of: lab.experiment) }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                    knobs(for: lab.experiment)
                }

                Divider()
                Button {
                    saveFrame()
                } label: {
                    Label("Save Frame…", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .ringGlassButtonStyle()
                if let savedFrameMessage {
                    Text(savedFrameMessage).font(.caption2).foregroundStyle(.tertiary)
                }
                Text("A still of the stage at 2×. Liquid Glass and RealityKit don't rasterise — Morph and Volumetric save empty.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.headline)
    }

    private func knobs(for experiment: LabExperiment) -> some View {
        ForEach(experiment.parameters) { parameter in
            LabSlider(title: parameter.name,
                      value: lab.binding(parameter, of: experiment),
                      range: parameter.range,
                      format: parameter.format,
                      help: parameter.help)
        }
    }

    private var paletteStrip: some View {
        HStack(spacing: 4) {
            ForEach(Array(colors(at: 0).enumerated()), id: \.offset) { _, c in
                RoundedRectangle(cornerRadius: 4).fill(c).frame(height: 14)
            }
        }
    }

    /// A PNG of the stage, 2×, to the Desktop. `ImageRenderer` runs the
    /// shaders — it is how every one of them was checked — so what is
    /// saved is what is on screen for everything but the two that live
    /// outside Core Graphics.
    private func saveFrame() {
        let f = frame(at: Date(), diameter: CGFloat(lab.diameter))
        let view = ZStack {
            lab.darkStage ? Color(white: 0.06) : Color(white: 0.94)
            LabExperimentView(experiment: lab.experiment, frame: f, config: config, post: lab.post)
        }
        .frame(width: CGFloat(lab.diameter) * 1.4, height: CGFloat(lab.diameter) * 1.4)
        .environment(\.colorScheme, lab.darkStage ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { savedFrameMessage = "Couldn't render."; return }
        let stamp = Date().formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".").replacingOccurrences(of: " ", with: "_")
        let name = "Lab \(lab.experiment.name) \(stamp).png"
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let url = desktop.appendingPathComponent(name)
        #if canImport(AppKit)
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else { savedFrameMessage = "Couldn't encode."; return }
        #else
        guard let data = UIImage(cgImage: cg).pngData() else { savedFrameMessage = "Couldn't encode."; return }
        #endif
        do {
            try data.write(to: url)
            savedFrameMessage = "Saved \(name) to the Desktop."
        } catch {
            savedFrameMessage = "Couldn't save: \(error.localizedDescription)"
        }
    }
}

/// Bass / mid / treble / beat, live.
struct LabBandMeters: View {
    let bands: LabAudioBands

    var body: some View {
        VStack(spacing: 4) {
            row("Level", bands.level)
            row("Bass", bands.bass)
            row("Mid", bands.mid)
            row("Treble", bands.treble)
            row("Beat", bands.beat)
        }
    }

    private func row(_ name: String, _ v: Double) -> some View {
        HStack(spacing: 8) {
            Text(name).font(.caption2).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
            LabMeter(level: min(v, 1))
        }
    }
}

struct LabSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: String = "%.2f"
    var help: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
            if let help {
                Text(help)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct LabMeter: View {
    let level: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(.tint).frame(width: geo.size.width * level)
            }
        }
        .frame(height: 6)
        .accessibilityLabel("Audio level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }
}

/// The experiments as a list, for the sidebar column. Cross-platform so
/// the iOS app can get the Lab later without a second list.
public struct LabListView: View {
    @ObservedObject var lab: LabState

    public init(lab: LabState) { self.lab = lab }

    public var body: some View {
        // A `Binding<LabExperiment?>` rather than the non-optional
        // selection: that initializer is macOS-only, and this list is
        // meant to reach the iOS app too.
        let selection = Binding<LabExperiment?>(
            get: { lab.experiment },
            set: { if let it = $0 { lab.experiment = it } }
        )
        List(selection: selection) {
            ForEach(LabSection.allCases) { section in
                Section {
                    ForEach(section.bases) { row($0) }
                    if !section.posts.isEmpty {
                        Text("Post effects — stack these over any base")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .listRowSeparator(.hidden)
                        ForEach(section.posts) { row($0) }
                    }
                } header: {
                    Label(section.title, systemImage: section.symbol)
                }
            }
        }
    }

    private func row(_ experiment: LabExperiment) -> some View {
        HStack(spacing: 10) {
            Image(systemName: experiment.symbol)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(experiment.name)
                Text(experiment.technology)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .tag(experiment)
    }
}

/// One experiment, drawn. Public so a harness can render the 2D ones
/// offscreen through `ImageRenderer` — the way every shader in this
/// package has been checked, since the CLI cannot screenshot the app.
public struct LabExperimentView: View {
    let experiment: LabExperiment
    let frame: LabFrame
    @ObservedObject var config: RingConfig
    /// Post effects over the base, in order.
    var post: [LabPostEffect] = []

    public init(experiment: LabExperiment, frame: LabFrame, config: RingConfig, post: [LabPostEffect] = []) {
        self.experiment = experiment
        self.frame = frame
        self.config = config
        self.post = post
    }

    public var body: some View {
        // Fill: scale the base so its content spans the disc. The post
        // stack and the glyph sit outside the scale, so a bloom's reach
        // and the glyph's size are unaffected.
        let scale = 1 + frame.fill * (1 / experiment.naturalFill - 1)
        LabPostStack(effects: post, frame: frame) {
            ZStack {
                base.scaleEffect(scale)
                LabGlyphOverlay(frame: frame)
            }
        }
    }

    @ViewBuilder
    private var base: some View {
        switch experiment {
        case .aurora:
            LabAuroraView(frame: frame)
        case .orb:
            LabOrbView(frame: frame)
        case .bloom:
            LabBloomView(frame: frame) { ring }
        case .ripple:
            LabRippleView(frame: frame) { ring }
        case .mesh:
            LabMeshView(frame: frame)
        case .swarm:
            ZStack {
                ring
                LabSwarmView(frame: frame)
            }
        case .sparks:
            ZStack {
                ring
                LabSparksView(frame: frame)
            }
        case .volumetric:
            LabVolumetricView(frame: frame)
        case .refraction:
            LabRefractionView(frame: frame) { ring }
        case .chromatic:
            LabChromaticView(frame: frame) { ring }
        case .morph:
            LabMorphView(frame: frame, config: config)
        case .liquid:
            LabLiquidView(frame: frame)
        case .rays:
            LabRaysView(frame: frame) { ring }
        case .sphere:
            LabSphereView(frame: frame)
        case .tunnel:
            LabTunnelView(frame: frame)
        case .constellation:
            LabConstellationView(frame: frame)
        case .harmonograph:
            LabHarmonographView(frame: frame)
        case .ink:
            LabInkView(frame: frame)
        case .kaleido:
            LabKaleidoView(frame: frame) { ring }
        case .dots:
            LabDotsView(frame: frame) { ring }
        case .grain:
            LabGrainView(frame: frame) { ring }
        case .cells:
            LabCellsView(frame: frame)
        case .warp:
            LabWarpView(frame: frame)
        case .symbols:
            LabSymbolsView(frame: frame)
        case .shapeshift:
            LabShapeshiftView(frame: frame)
        case .glitch:
            LabGlitchView(frame: frame) { ring }
        case .crt:
            LabCRTView(frame: frame) { ring }
        case .neon:
            LabNeonView(frame: frame) { ring }
        case .frost:
            LabFrostView(frame: frame) { ring }
        case .duotone:
            LabDuotoneView(frame: frame) { ring }
        case .spin:
            LabSpinView(frame: frame) { ring }
        case .lattice:
            LabLatticeView(frame: frame)
        case .stipple:
            LabStippleView(frame: frame)
        case .tiles:
            LabTilesView(frame: frame) { ring }
        case .bubble:
            LabBubbleView(frame: frame)
        case .slices:
            LabSlicesView(frame: frame)
        case .stack:
            LabStackView(frame: frame)
        case .cascade:
            LabCascadeView(frame: frame)
        case .prism:
            LabPrismView(frame: frame)
        case .chrome:
            LabChromeView(frame: frame) { ring }
        case .holo:
            LabHoloView(frame: frame)
        case .lenticular:
            LabLenticularView(frame: frame)
        case .moire:
            LabMoireView(frame: frame)
        case .orrery:
            LabOrreryView(frame: frame)
        case .bokeh:
            LabBokehView(frame: frame)
        case .frostOrb:
            LabFrostOrbView(frame: frame)
        case .globe:
            LabGlobeView(frame: frame)
        case .silk:
            LabSilkView(frame: frame)
        case .liquidRing:
            LabLiquidRingView(frame: frame)
        case .tide:
            LabTideView(frame: frame)
        case .droplet: LabDropletView(frame: frame)
        case .pour: LabPourView(frame: frame)
        case .pool: LabPoolView(frame: frame)
        case .caustics: LabCausticsView(frame: frame)
        case .lava: LabLavaView(frame: frame)
        case .jelly: LabJellyView(frame: frame)
        case .slick: LabSlickView(frame: frame)
        case .deep: LabDeepView(frame: frame)
        case .nebula: LabNebulaView(frame: frame)
        case .water: LabWaterView(frame: frame) { ring }
        case .haze: LabHazeView(frame: frame) { ring }
        case .fizz: LabFizzView(frame: frame) { ring }
        case .glints: LabGlintsView(frame: frame) { ring }
        case .parallax: LabParallaxView(frame: frame) { ring }
        case .focus: LabFocusView(frame: frame) { ring }
        case .buttonGlow: LabButtonGlowView(frame: frame, config: config)
        case .sheet: LabSheetView(frame: frame, config: config)
        case .hold: LabHoldView(frame: frame, config: config)
        case .journey:
            LabJourneyView(frame: frame, config: config)
        case .agentStates:
            LabAgentStatesView(frame: frame, config: config)
        case .waveform:
            LabWaveformView(frame: frame, config: config)
        case .edgeGlow:
            LabEdgeGlowView(frame: frame, config: config)
        case .caption:
            LabCaptionView(frame: frame, config: config)
        }
    }

    /// The ring as it is, for the experiments that decorate it. Sized to
    /// the same 72% of the stage the pod's ring is of its pod, so what
    /// you see is the pod's proportions. `overrideElapsed` ties it to the
    /// Lab's clock so offscreen renders are deterministic.
    private var ring: some View {
        RingView(config: config, diameter: frame.diameter * 0.72, overrideElapsed: frame.time)
            .frame(width: frame.diameter, height: frame.diameter)
    }
}
