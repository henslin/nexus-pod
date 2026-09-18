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
    @StateObject private var presets = LabPresetStore()
    @StateObject private var specs = LabSpecStore()
    @State private var appeared = Date()
    @State private var savedFrameMessage: String?
    @State private var stageSize: CGSize = .zero

    /// A stage location as points from the experiment's centre.
    private func pointerLocal(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x - stageSize.width / 2, y: p.y - stageSize.height / 2)
    }
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
                .frame(width: lab.experiment.isQBranch ? 420 : 300)
        }
        .onAppear { appeared = Date() }
        .onChange(of: lab.audioReactive, initial: true) { _, on in
            if on { audio.start() } else { audio.stop() }
        }
        .onChange(of: lab.audioAttack, initial: true) { _, v in audio.attack = v }
        .onChange(of: lab.audioRelease, initial: true) { _, v in audio.release = v }
        .onChange(of: lab.transcribe, initial: true) { _, on in audio.transcribing = on }
        .onDisappear { audio.stop() }
    }

    private func colors(at time: Double) -> [Color] {
        lab.colors(config: config, at: time)
    }

    private var bands: LabAudioBands { lab.bands(from: audio) }

    private func frame(at date: Date, diameter: CGFloat) -> LabFrame {
        lab.frame(at: date, since: appeared, diameter: diameter, config: config, audio: audio)
    }

    /// Flows, controls on a phone, and Q Branch draw on a real device;
    /// orbs on the disc stage.
    private var onDevice: Bool { lab.experiment.usesPhoneCanvas || lab.experiment == .system }

    @ViewBuilder
    private var stage: some View {
        if onDevice {
            #if os(macOS)
            deviceStage
            #else
            discStage
            #endif
        } else {
            discStage
        }
    }

    #if os(macOS)
    /// The main preview's stage, for the Lab: the iPhone frame on a
    /// pinch-to-zoom canvas, a floating bar with Light/Dark, the finish
    /// and App UI — the same controls as Nexus, so a flow is judged the
    /// way the ring is (Chris, 2026-09-16: "re-use what we have going on
    /// in the main Nexus area"). Q Branch adds its step strip below.
    private var deviceStage: some View {
        let screen = AnimationExporter.phoneScreenSize
        return ZoomableCanvas(contentSize: AnimationExporter.phoneFrameSize, minMagnification: 0.25, maxMagnification: 4, restMagnification: 1) {
            ZStack {
                TimelineView(.animation) { timeline in
                    let f = frame(at: timeline.date, diameter: 360).onScreen(screen)
                    Group {
                        if lab.experiment == .system {
                            LabPlayView(frame: f, config: config)
                        } else if lab.experiment == .app {
                            LabAppView(frame: f, config: config)
                        } else {
                            LabExperimentView(experiment: lab.experiment, frame: f, config: config, post: lab.activePost)
                        }
                    }
                    .id(lab.experiment)
                }
                .frame(width: screen.width, height: screen.height)
                .clipShape(RoundedRectangle(cornerRadius: AnimationExporter.phoneScreenCornerRadius, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture { if lab.experiment.isTappable { lab.advance() } }
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if lab.experiment.isHoldable { lab.beginHold() }
                        if lab.experiment.usesPointer { lab.pointer = CGPoint(x: g.location.x - screen.width / 2, y: g.location.y - screen.height / 2) }
                    }
                    .onEnded { _ in lab.endHold() })
                .onContinuousHover { phase in
                    guard lab.experiment.usesPointer else { return }
                    switch phase {
                    case .active(let p): lab.pointer = CGPoint(x: p.x - screen.width / 2, y: p.y - screen.height / 2)
                    case .ended: lab.pointer = nil
                    }
                }
                lab.finish.image
                    .resizable()
                    .frame(width: AnimationExporter.phoneFrameSize.width, height: AnimationExporter.phoneFrameSize.height)
                    .allowsHitTesting(false)
            }
            .frame(width: AnimationExporter.phoneFrameSize.width, height: AnimationExporter.phoneFrameSize.height)
            .environment(\.colorScheme, lab.darkStage ? .dark : .light)
        }
        // The scroll view would otherwise ask for the phone's full width
        // as its minimum and shove the rail off the edge in a narrow
        // window; the canvas can be smaller than the phone — that's what
        // the zoom is for.
        .frame(minWidth: 240, maxWidth: .infinity, minHeight: 240, maxHeight: .infinity)
        .clipped()
        .background(Color(nsColor: .underPageBackgroundColor))
        .overlay(alignment: .top) {
            deviceControls
                .padding(.top, 16)
        }
        .overlay(alignment: .bottom) {
            if lab.experiment == .system {
                TimelineView(.animation) { timeline in
                    LabPlayStrip(lab: lab, frame: frame(at: timeline.date, diameter: 360))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassBackground(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.bottom, 16)
            } else {
                Text("Pinch to zoom · double-click to reset")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassBackground(in: Capsule())
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The main preview's controls pill, verbatim in kind: Light/Dark,
    /// the finish, App UI.
    private var deviceControls: some View {
        HStack(spacing: 28) {
            Picker("Appearance", selection: $lab.darkStage) {
                Text("Light").tag(false)
                Text("Dark").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            Picker("Finish", selection: $lab.finish) {
                ForEach(AnimationExporter.DeviceFinish.allCases) { finish in
                    Text(finish.rawValue).tag(finish)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 150)
            Toggle("App UI", isOn: $lab.appUI)
                .toggleStyle(.switch)
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassBackground(in: Capsule())
    }
    #endif

    private var discStage: some View {
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
                    } else if lab.experiment == .system {
                        ScrollView(.vertical) {
                            LabSystemStage(lab: lab, config: config, frame: f)
                                .padding(.vertical, 24)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        LabExperimentView(experiment: lab.experiment, frame: f, config: config, post: lab.activePost)
                    }
                }
                .id(lab.experiment)
                .environment(\.colorScheme, lab.darkStage ? .dark : .light)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                if lab.experiment.isTappable, !lab.experiment.isQBranch { lab.advance() }
            }
            // Press and hold, for the Hold flow: begins on touch-down,
            // ends on release — `DragGesture(minimumDistance: 0)` is the
            // one gesture that reports both.
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if lab.experiment.isHoldable, !lab.experiment.isQBranch { lab.beginHold() }
                    if lab.experiment.usesPointer { lab.pointer = pointerLocal(g.location) }
                }
                .onEnded { _ in lab.endHold() })
            .onContinuousHover { phase in
                guard lab.experiment.usesPointer else { return }
                switch phase {
                case .active(let p): lab.pointer = pointerLocal(p)
                case .ended: lab.pointer = nil
                }
            }
            .background(GeometryReader { geo in Color.clear.onAppear { stageSize = geo.size }.onChange(of: geo.size) { _, s in stageSize = s } })
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
                                              post: lab.activePost)
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

    /// The inspector: the experiment's rail, or — in Q Branch — the board.
    @ViewBuilder
    private var controls: some View {
        if lab.experiment.isQBranch {
            ScrollView {
                LabSpecBoard(lab: lab, config: config, frame: frame(at: Date(), diameter: 360), specs: specs,
                             frameAt: { frame(at: $0, diameter: 360) })
            }
        } else {
            LabRailView(lab: lab, config: config, audio: audio, presets: presets, bands: bands,
                        onSaveFrame: saveFrame, savedFrameMessage: savedFrameMessage)
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
            LabExperimentView(experiment: lab.experiment, frame: f, config: config, post: lab.activePost)
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

/// A number: label · slider · field with its unit, on one row. The help
/// is a tooltip, not a caption — the inspector idiom (Chris, 2026-09-16:
/// "more like Sketch"). Arrow keys step the field; ⇧ steps by ten.
struct LabSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: String = "%.2f"
    var help: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: LabRailMetrics.labelWidth, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
            Slider(value: $value, in: range)
                .controlSize(.small)
            LabNumberField(value: $value, range: range, format: format)
        }
        .help(help ?? title)
    }
}

/// The inspector's shared measures.
enum LabRailMetrics {
    static let labelWidth: CGFloat = 84
    static let fieldWidth: CGFloat = 64
}

/// A numeric field showing the value in its unit ("550 ms", "1.0×"),
/// editable; arrow keys step it by a hundredth of the range, ⇧ by a
/// tenth.
struct LabNumberField: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    @State private var text = ""
    @FocusState private var focused: Bool

    private var shown: String { String(format: format, value) }
    private var step: Double { (range.upperBound - range.lowerBound) / 100 }

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .font(.caption.monospacedDigit())
            .multilineTextAlignment(.trailing)
            .frame(width: LabRailMetrics.fieldWidth)
            .focused($focused)
            .onAppear { text = shown }
            .onChange(of: value) { _, _ in if !focused { text = shown } }
            .onChange(of: focused) { _, f in if !f { commit() } }
            .onSubmit { commit() }
            .onKeyPress(.upArrow) { nudge(+1); return .handled }
            .onKeyPress(.downArrow) { nudge(-1); return .handled }
    }

    private func commit() {
        // The leading number, in any unit.
        let scanner = Scanner(string: text.replacingOccurrences(of: ",", with: "."))
        if let v = scanner.scanDouble() { value = min(range.upperBound, max(range.lowerBound, v)) }
        text = shown
    }

    private func nudge(_ dir: Double) {
        #if canImport(AppKit)
        let big = NSEvent.modifierFlags.contains(.shift)
        #else
        let big = false
        #endif
        let s = step * (big ? 10 : 1) * dir
        value = min(range.upperBound, max(range.lowerBound, value + s))
        text = shown
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
                    if section == .orb {
                        // Sixty bases read as six shelves.
                        ForEach(section.families, id: \.family) { family, bases in
                            Text(family.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .listRowSeparator(.hidden)
                                .padding(.top, 4)
                            ForEach(bases) { row($0) }
                        }
                    } else {
                        ForEach(section.bases) { row($0) }
                    }
                    if !section.posts.isEmpty {
                        Text("Post effects")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                            .padding(.top, 4)
                        ForEach(section.posts) { row($0) }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(section.title, systemImage: section.symbol)
                        Text(section.caption)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .textCase(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
        .help(experiment.summary)
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
        case .thinkingOrbs: LabThinkingOrbsView(frame: frame)
        case .orbKit: LabOrbKitView(frame: frame)
        case .beamKit: LabBeamKitView(frame: frame)
        case .matrixOrb: LabMatrixOrbView(frame: frame)
        case .voiceOrb: LabVoiceOrbView(frame: frame)
        case .orb21: LabOrb21View(frame: frame)
        case .gooey: LabGooeyView(frame: frame, config: config)
        case .metal: LabMetalView(frame: frame, config: config)
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
        case .system:
            LabPlayView(frame: frame, config: config)
        case .app:
            LabAppView(frame: frame, config: config)
        case .askButton:
            LabAskButtonView(frame: frame, config: config)
        case .quidgets:
            LabQuidgetsView(frame: frame)
        case .sunflower:
            LabSunflowerView(frame: frame, config: config)
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

/// One knob, drawn as the control its kind calls for — see
/// `LabParameter.control`: a slider with a field, a segmented control
/// (whose options' settings follow it), a popup, or a checkbox. Help is
/// a tooltip on every one.
public struct LabKnob: View {
    let parameter: LabParameter
    @Binding var value: Double

    public init(parameter: LabParameter, value: Binding<Double>) {
        self.parameter = parameter
        self._value = value
    }

    private var index: Binding<Int> {
        Binding(get: { Int((value - parameter.range.lowerBound).rounded()) },
                set: { value = parameter.range.lowerBound + Double($0) })
    }

    public var body: some View {
        switch parameter.control {
        case .slider:
            LabSlider(title: parameter.name, value: $value, range: parameter.range, format: parameter.format, help: parameter.help)
        case .checkbox:
            HStack(spacing: 8) {
                Spacer().frame(width: LabRailMetrics.labelWidth)
                Toggle(parameter.name, isOn: Binding(get: { value >= 0.5 }, set: { value = $0 ? 1 : 0 }))
                    .font(.callout)
                Spacer(minLength: 0)
            }
            .help(parameter.help.isEmpty ? parameter.name : parameter.help)
        case .popup:
            HStack(spacing: 8) {
                Text(parameter.name)
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(width: LabRailMetrics.labelWidth, alignment: .leading)
                    .lineLimit(1)
                Picker("", selection: index) {
                    ForEach(Array((parameter.choices ?? []).enumerated()), id: \.offset) { i, label in
                        Text(label).tag(i)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                Spacer(minLength: 0)
            }
            .help(parameter.help.isEmpty ? parameter.name : parameter.help)
        case .segmented:
            VStack(alignment: .leading, spacing: 4) {
                Text(parameter.name).font(.callout).foregroundStyle(.secondary)
                Picker("", selection: index) {
                    ForEach(Array((parameter.choices ?? []).enumerated()), id: \.offset) { i, label in
                        Text(label).tag(i)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
            }
            .help(parameter.help.isEmpty ? parameter.name : parameter.help)
        }
    }
}

/// A row of chips — capsules, one selected — wrapping onto more rows
/// when there are many. Glass-styled selection like the aspect switcher.
public struct LabChips: View {
    let choices: [String]
    @Binding var selection: Int

    public init(choices: [String], selection: Binding<Int>) {
        self.choices = choices
        self._selection = selection
    }

    public var body: some View {
        LabWrap(spacing: 6) {
            ForEach(Array(choices.enumerated()), id: \.offset) { i, label in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = i }
                } label: {
                    Text(label)
                        .font(.callout)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(i == selection ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.fill.quaternary)))
                        .overlay(Capsule().strokeBorder(i == selection ? Color.primary.opacity(0.25) : .clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A wrapping HStack, for chips and words. `Layout`, so it works on
/// both platforms; rows can be centred.
public struct LabWrap: Layout {
    var spacing: CGFloat = 6
    var alignment: HorizontalAlignment = .leading
    public init(spacing: CGFloat = 6, alignment: HorizontalAlignment = .leading) {
        self.spacing = spacing
        self.alignment = alignment
    }

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[(Int, CGSize)]] {
        var rows: [[(Int, CGSize)]] = [[]]
        var x: CGFloat = 0
        for (i, v) in subviews.enumerated() {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, !rows[rows.count - 1].isEmpty { rows.append([]); x = 0 }
            rows[rows.count - 1].append((i, s))
            x += s.width + spacing
        }
        return rows
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var y: CGFloat = 0
        for (r, row) in rows(subviews, width: width).enumerated() {
            let h = row.map(\.1.height).max() ?? 0
            y += h + (r > 0 ? spacing : 0)
        }
        return CGSize(width: width, height: y)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            let h = row.map(\.1.height).max() ?? 0
            let w = row.reduce(0) { $0 + $1.1.width } + spacing * CGFloat(max(0, row.count - 1))
            var x: CGFloat = bounds.minX
            if alignment == .center { x = bounds.minX + (bounds.width - w) / 2 }
            else if alignment == .trailing { x = bounds.maxX - w }
            for (i, s) in row {
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
            y += h + spacing
        }
    }
}

/// The Presets menu for the current experiment: apply one, save the
/// current knobs as one, delete one.
struct LabPresetsMenu: View {
    @ObservedObject var presets: LabPresetStore
    @ObservedObject var lab: LabState
    @Binding var saving: Bool
    @Binding var name: String

    @ObservedObject private var defaults = LabDefaultsStore.shared
    @State private var confirmingReset = false

    var body: some View {
        let mine = presets.presets(for: lab.experiment)
        Menu {
            // The default: what this experiment opens with and Reset
            // returns to. Set it as you go through each one.
            Button {
                defaults.set(from: lab)
            } label: {
                Label(defaults.has(lab.experiment) ? "Update Default" : "Make This the Default", systemImage: "pin")
            }
            if defaults.has(lab.experiment) {
                Button("Forget Pin (Back to Baked)", role: .destructive) { defaults.forget(lab.experiment) }
            }
            Divider()
            if mine.isEmpty {
                Text("No presets yet")
            } else {
                ForEach(mine) { p in
                    Button(p.name) { presets.apply(p, to: lab) }
                }
                Divider()
                Menu("Delete") {
                    ForEach(mine) { p in Button(p.name, role: .destructive) { presets.delete(p) } }
                }
            }
            Divider()
            Button("Save Preset…") { saving = true }
            Divider()
            Button("Reset Everything to Factory…", role: .destructive) { confirmingReset = true }
        } label: {
            Label("Presets", systemImage: defaults.has(lab.experiment) ? "pin.fill" : "square.stack").font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(defaults.has(lab.experiment) ? "This experiment has a default you set." : "Presets, and the default this experiment opens with.")
        .confirmationDialog("Reset everything to factory?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset Everything", role: .destructive) { lab.resetEverything() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every knob, every pin you've made since the bake, the post stacks, the hero and the Q Branch spec go back to the baked defaults — your pass of 17 September. Presets and reviews stay.")
        }
    }
}
