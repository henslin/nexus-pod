import SwiftUI

// The Lab's inspector — the rail beside the stage.
//
// Rebuilt overnight 2026-09-15/16 (Chris: "spacing etc is a bit off").
// The old rail was one long list: stage knobs, colour, audio, twenty-two
// post-effect toggles, and only then the experiment's own knobs. The
// order is now the order of use — the thing you are tuning first, what
// is stacked on it second, the room it is judged in after — and every
// section is a disclosure that remembers whether you left it open.
// Post effects are a stack you add to, not a wall of switches.

/// One collapsible section of the rail, with its open state kept
/// across launches by id.
struct LabRailSection<Content: View, Trailing: View>: View {
    let id: String
    let title: String
    var defaultOpen = true
    @ViewBuilder let content: () -> Content
    @ViewBuilder let trailing: () -> Trailing
    @AppStorage private var open: Bool

    init(_ id: String, _ title: String, defaultOpen: Bool = true,
         @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.id = id
        self.title = title
        self.defaultOpen = defaultOpen
        self.content = content
        self.trailing = trailing
        _open = AppStorage(wrappedValue: defaultOpen, "nexus.lab.rail.\(id)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { open.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .rotationEffect(.degrees(open ? 90 : 0))
                            .foregroundStyle(.secondary)
                            .frame(width: 10)
                        Text(title).font(.headline)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                trailing()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            if open {
                VStack(alignment: .leading, spacing: 12) {
                    content()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
            Divider()
        }
    }
}

/// The rail for one experiment.
public struct LabRailView: View {
    @ObservedObject var lab: LabState
    @ObservedObject var config: RingConfig
    @ObservedObject var audio: AudioSpectrumMonitor
    @ObservedObject var presets: LabPresetStore
    let bands: LabAudioBands
    let onSaveFrame: () -> Void
    let savedFrameMessage: String?

    @State private var savingPreset = false
    @State private var presetName = ""
    /// Which post effect's knobs are open.
    @State private var openPost: LabPostEffect?

    /// For harnesses: the rail's content without its scroll view, which
    /// `ImageRenderer` can't rasterise on the Mac.
    public static func harness(lab: LabState, config: RingConfig) -> some View {
        LabRailView(lab: lab, config: config, audio: AudioSpectrumMonitor(), presets: LabPresetStore(), bands: LabAudioBands(), onSaveFrame: {}, savedFrameMessage: nil)
            .content
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let target = lab.target {
                targetBanner(target)
                Divider()
            }
            experimentSection
            postSection
            stageSection
            colourSection
            audioSection
            exportSection
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                if let target = lab.target {
                    targetBanner(target)
                    Divider()
                }
                experimentSection
                postSection
                stageSection
                colourSection
                audioSection
                exportSection
            }
        }
        .alert("Save Preset", isPresented: $savingPreset) {
            TextField("Name", text: $presetName)
            Button("Save") { if !presetName.isEmpty { presets.save(presetName, from: lab); presetName = "" } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The \(lab.experiment.name) knobs, the post stack, the hero and the palette.")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(lab.experiment.name).font(.title3.weight(.semibold))
                Spacer()
                if lab.experiment.canBeHero || lab.experiment == .gooey {
                    LabUseAsMenu(lab: lab)
                }
            }
            Text(lab.experiment.technology)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(lab.experiment.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // The hero is the first decision on a flow or a control, so
            // it sits up here rather than in the Stage disclosure.
            if lab.experiment.drawsHero {
                Picker("Hero", selection: $lab.hero) {
                    Text("Ring").tag(LabExperiment?.none)
                    ForEach(LabExperiment.allCases.filter(\.canBeHero)) { e in
                        Text(e.name).tag(LabExperiment?.some(e))
                    }
                }
                .pickerStyle(.menu)
                .padding(.top, 4)
                Text("What this draws where the ring goes — any orb, with the post stack.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
    }

    /// Q Branch sent you here to choose for a slot: say so, and offer
    /// the one gesture that finishes the errand.
    private func targetBanner(_ target: LabSlotTarget) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Choosing for \(target.label)", systemImage: "wrench.and.screwdriver")
                .font(.subheadline.weight(.semibold))
            Text(target.hint)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button {
                    lab.fulfilTarget()
                } label: {
                    Label("Use \(lab.experiment.name)", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .ringGlassButtonStyle()
                .disabled(!target.accepts(lab.experiment))
                Button("Cancel") { lab.target = nil; lab.experiment = .system }
                    .buttonStyle(.borderless)
            }
            if !target.accepts(lab.experiment) {
                Text("Pick an orb base for this slot.").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(Color.accentColor.opacity(0.08))
    }

    // MARK: Sections

    @ViewBuilder
    private var experimentSection: some View {
        if !lab.experiment.parameters.isEmpty {
            LabRailSection("knobs", lab.experiment.name) {
                LabKnobList(lab: lab, experiment: lab.experiment)
            } trailing: {
                LabPresetsMenu(presets: presets, lab: lab, saving: $savingPreset, name: $presetName)
                Button("Reset") { lab.resetParameters(of: lab.experiment) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
    }

    private var postSection: some View {
        LabRailSection("post", "Post Effects") {
            if lab.post.isEmpty {
                Text("Nothing stacked. Effects apply over the base, in order.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            ForEach(lab.post) { effect in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { openPost = openPost == effect ? nil : effect }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .rotationEffect(.degrees(openPost == effect ? 90 : 0))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 10)
                                Text(effect.experiment.name).font(.subheadline.weight(.medium))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button { lab.movePost(effect, by: -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless).disabled(lab.post.first == effect)
                        Button { lab.movePost(effect, by: 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless).disabled(lab.post.last == effect)
                        Button { lab.togglePost(effect); if openPost == effect { openPost = nil } } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless)
                    }
                    .font(.caption)
                    if openPost == effect {
                        LabKnobList(lab: lab, experiment: effect.experiment)
                            .padding(.leading, 16)
                    }
                }
            }
            Menu {
                ForEach(LabPostEffect.allCases.filter { !lab.post.contains($0) }) { effect in
                    Button {
                        lab.togglePost(effect)
                        openPost = effect
                    } label: {
                        Label(effect.experiment.name, systemImage: effect.experiment.symbol)
                    }
                }
            } label: {
                Label("Add Effect", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var stageSection: some View {
        LabRailSection("stage", "Stage", defaultOpen: false) {
            LabSlider(title: "Intensity", value: $lab.intensity, range: 0...1)
            LabSlider(title: "Speed", value: $lab.speed, range: 0.1...3, format: "%.1f×")
            LabSlider(title: "Size", value: $lab.diameter, range: 62...600, format: "%.0f pt")
            LabSlider(title: "Fill", value: $lab.fill, range: 0...1.3,
                      help: "Scales the experiment to fill the circle. 1 is edge to edge; past it crops.")
            Toggle("Dark Stage", isOn: $lab.darkStage)
            if !lab.experiment.usesPhoneCanvas {
                Toggle("Pod Preview", isOn: $lab.showPod)
                if lab.showPod {
                    Toggle("Fill Pod", isOn: $lab.podFill)
                        .padding(.leading, 12)
                }
            }
        }
    }

    private var colourSection: some View {
        LabRailSection("colour", "Colour", defaultOpen: false) {
            Picker("Palette", selection: $lab.palette) {
                ForEach(LabPalette.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            HStack(spacing: 4) {
                ForEach(Array(lab.colors(config: config, at: 0).enumerated()), id: \.offset) { _, c in
                    RoundedRectangle(cornerRadius: 4).fill(c).frame(height: 14)
                }
            }
            LabSlider(title: "Hue Drift", value: $lab.hueDrift, range: -90...90, format: "%.0f°/s",
                      help: "Rotates every colour's hue over time. The palette's relationships hold.")
            TextField("Glyph (SF Symbol)", text: $lab.glyph)
            Text("Drawn inside. Orb, Refraction, Liquid and Sphere are the ones built for it.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var audioSection: some View {
        LabRailSection("audio", "Audio", defaultOpen: false) {
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
                LabBandMeters(bands: bands)
                Toggle("Live Transcript", isOn: $lab.transcribe)
                Text(audio.transcriptError ?? (lab.transcribe ? "Speech recognition on the mic — Bloom Field and the Transcript adornment show your words as you say them." : "Off: the transcript surfaces show sample copy."))
                    .font(.caption2).foregroundStyle(audio.transcriptError == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.red))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var exportSection: some View {
        LabRailSection("export", "Export", defaultOpen: false) {
            Button {
                onSaveFrame()
            } label: {
                Label("Save Frame…", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .ringGlassButtonStyle()
            if let savedFrameMessage {
                Text(savedFrameMessage).font(.caption2).foregroundStyle(.tertiary)
            }
            Text("A still of the stage at 2×, to the Desktop. Liquid Glass and RealityKit don't rasterise — Morph and Volumetric save empty.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// An experiment's knobs, with a heading wherever the group changes.
struct LabKnobList: View {
    @ObservedObject var lab: LabState
    let experiment: LabExperiment

    var body: some View {
        let params = experiment.parameters
        ForEach(Array(params.enumerated()), id: \.element.id) { i, parameter in
            // A heading wherever the group changes — unless the group is
            // one knob wearing the group's own name, which would say it
            // twice.
            if let g = parameter.group, i == 0 || params[i - 1].group != g,
               !(g == parameter.name && (i + 1 >= params.count || params[i + 1].group != g)) {
                Text(g)
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, i == 0 ? 0 : 6)
            }
            LabKnob(parameter: parameter, value: lab.binding(parameter, of: experiment))
        }
    }
}
