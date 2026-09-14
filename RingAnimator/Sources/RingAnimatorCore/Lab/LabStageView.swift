import SwiftUI

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
    @StateObject private var audio = AudioLevelMonitor()
    @State private var appeared = Date()

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
                .frame(width: 280)
        }
        .onAppear { appeared = Date() }
        .onChange(of: lab.audioReactive, initial: true) { _, on in
            if on { audio.start() } else { audio.stop() }
        }
        .onDisappear { audio.stop() }
    }

    private var colors: [Color] {
        [config.primaryColor, config.secondaryColor] + config.additionalColors
    }

    private var stage: some View {
        ZStack {
            (lab.darkStage ? Color(white: 0.06) : Color(white: 0.94))
            TimelineView(.animation) { timeline in
                let elapsed = timeline.date.timeIntervalSince(appeared) * lab.speed
                let level = lab.audioReactive ? min(audio.level * lab.audioSensitivity, 1.5) : 0
                let frame = LabFrame(time: elapsed,
                                     intensity: lab.intensity,
                                     audio: level,
                                     colors: colors,
                                     diameter: CGFloat(lab.diameter),
                                     darkStage: lab.darkStage,
                                     params: lab.resolvedParameters(of: lab.experiment))
                experiment(frame)
                    .id(lab.experiment)
                    .environment(\.colorScheme, lab.darkStage ? .dark : .light)
            }
        }
    }

    private func experiment(_ frame: LabFrame) -> some View {
        LabExperimentView(experiment: lab.experiment, frame: frame, config: config)
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

                LabSlider(title: "Intensity", value: $lab.intensity, range: 0...1)
                LabSlider(title: "Speed", value: $lab.speed, range: 0.1...3, format: "%.1f×")
                LabSlider(title: "Size", value: $lab.diameter, range: 62...600, format: "%.0f pt")

                Toggle("Audio Reactive", isOn: $lab.audioReactive)
                if lab.audioReactive {
                    LabSlider(title: "Sensitivity", value: $lab.audioSensitivity, range: 0.5...5, format: "%.1f×")
                    LabMeter(level: min(audio.level * lab.audioSensitivity, 1))
                }
                Toggle("Dark Stage", isOn: $lab.darkStage)

                if !lab.experiment.parameters.isEmpty {
                    Divider()
                    HStack {
                        Text(lab.experiment.name).font(.headline)
                        Spacer()
                        Button("Reset") { lab.resetParameters(of: lab.experiment) }
                            .buttonStyle(.borderless)
                            .font(.caption)
                    }
                    ForEach(lab.experiment.parameters) { parameter in
                        LabSlider(title: parameter.name,
                                  value: lab.binding(parameter, of: lab.experiment),
                                  range: parameter.range,
                                  format: parameter.format,
                                  help: parameter.help)
                    }
                }

                Divider()

                Text("Colours come from the Nexus animation's palette — change them in Controls and every experiment follows.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
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
        List(LabExperiment.allCases, selection: selection) { experiment in
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
}

/// One experiment, drawn. Public so a harness can render the 2D ones
/// offscreen through `ImageRenderer` — the way every shader in this
/// package has been checked, since the CLI cannot screenshot the app.
public struct LabExperimentView: View {
    let experiment: LabExperiment
    let frame: LabFrame
    @ObservedObject var config: RingConfig

    public init(experiment: LabExperiment, frame: LabFrame, config: RingConfig) {
        self.experiment = experiment
        self.frame = frame
        self.config = config
    }

    public var body: some View {
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
