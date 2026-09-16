import SwiftUI

// The Lab's inspector — the rail beside the stage.
//
// Rebuilt 2026-09-16 in the inspector idiom (Chris: "more like Sketch …
// they do a great job of balancing what should be exposed and
// collapsing the rest"). Every knob is drawn as the control its kind
// calls for (`LabParameter.control`); numbers are label · slider · field
// on one row; help is a tooltip, never a caption; a collapsed section
// still shows its values in its header; post effects are a list of
// applied things with a checkbox each, a "+" to add, and their own
// disclosure — Sketch's Fills. Only the sections that apply are drawn.

/// One collapsible section of the rail. Its open state is kept across
/// launches by id, and the header carries a summary of what's inside
/// while it's closed.
struct LabRailSection<Content: View, Trailing: View>: View {
    let id: String
    let title: String
    var summary: String? = nil
    var defaultOpen = true
    @ViewBuilder let content: () -> Content
    @ViewBuilder let trailing: () -> Trailing
    @AppStorage private var open: Bool

    init(_ id: String, _ title: String, summary: String? = nil, defaultOpen: Bool = true,
         @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.id = id
        self.title = title
        self.summary = summary
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
                        Text(title).font(.subheadline.weight(.semibold))
                        if !open, let summary, !summary.isEmpty {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                trailing()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            if open {
                VStack(alignment: .leading, spacing: 8) {
                    content()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
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
            aboutSection
            experimentSection
            if !lab.experiment.usesPhoneCanvas {
                postSection
            }
            stageSection
            colourSection
            audioSection
            exportSection
        }
    }

    public var body: some View {
        ScrollView {
            content
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(lab.experiment.name).font(.headline)
                    Text("\(lab.experiment.section.title) · \(lab.experiment.technology)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if lab.experiment.canBeHero || lab.experiment == .gooey || lab.experiment == .askButton {
                    LabUseAsMenu(lab: lab)
                }
            }
            // The hero is the first decision on a flow or a control.
            if lab.experiment.drawsHero {
                HStack(spacing: 8) {
                    Text("Hero")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(width: LabRailMetrics.labelWidth, alignment: .leading)
                    Picker("", selection: $lab.hero) {
                        Text("Ring").tag(LabExperiment?.none)
                        ForEach(LabExperiment.allCases.filter(\.canBeHero)) { e in
                            Text(e.name).tag(LabExperiment?.some(e))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    Spacer(minLength: 0)
                }
                .help("What this draws where the ring goes — any orb, with the post stack.")
            }
        }
        .padding(14)
    }

    /// Q Branch sent you here to choose for a slot: say so, and offer
    /// the one gesture that finishes the errand.
    private func targetBanner(_ target: LabSlotTarget) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Choosing for \(target.label)", systemImage: "wrench.and.screwdriver")
                .font(.subheadline.weight(.semibold))
            HStack {
                Button {
                    lab.fulfilTarget()
                } label: {
                    Label("Use \(lab.experiment.name)", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .ringGlassButtonStyle()
                .disabled(!target.accepts(lab.experiment))
                .help(target.hint)
                Button("Cancel") { lab.target = nil; lab.experiment = .system }
                    .buttonStyle(.borderless)
            }
            if !target.accepts(lab.experiment) {
                Text("Pick an orb for this slot.").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.08))
    }

    // MARK: Sections

    private var aboutSection: some View {
        LabRailSection("about", "About", defaultOpen: false) {
            Text(lab.experiment.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var experimentSection: some View {
        if !lab.experiment.parameters.isEmpty {
            LabRailSection("knobs", lab.experiment.name) {
                LabKnobList(lab: lab, experiment: lab.experiment)
            } trailing: {
                LabPresetsMenu(presets: presets, lab: lab, saving: $savingPreset, name: $presetName)
                Button {
                    lab.resetParameters(of: lab.experiment)
                } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help("Reset the knobs")
            }
        }
    }

    private var postSection: some View {
        let summary = lab.post.isEmpty ? "None" : lab.post.map { $0.experiment.name + (lab.disabledPost.contains($0) ? " (off)" : "") }.joined(separator: " · ")
        return LabRailSection("post", "Post Effects", summary: summary) {
            if lab.post.isEmpty {
                Text("Nothing stacked. Effects apply over the base, in order.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            ForEach(lab.post) { effect in
                postRow(effect)
            }
        } trailing: {
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
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Add an effect over the base")
        }
    }

    /// Sketch's fill row: a checkbox to apply it, its name, a disclosure
    /// to its knobs, and a menu to move or remove it.
    private func postRow(_ effect: LabPostEffect) -> some View {
        let on = !lab.disabledPost.contains(effect)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(get: { on }, set: { v in
                    if v { lab.disabledPost.remove(effect) } else { lab.disabledPost.insert(effect) }
                }))
                .labelsHidden()
                .help(on ? "Applied" : "Kept, not applied")
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { openPost = openPost == effect ? nil : effect }
                } label: {
                    HStack(spacing: 6) {
                        Text(effect.experiment.name)
                            .font(.callout)
                            .foregroundStyle(on ? .primary : .secondary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .rotationEffect(.degrees(openPost == effect ? 90 : 0))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Menu {
                    Button("Move Up") { lab.movePost(effect, by: -1) }.disabled(lab.post.first == effect)
                    Button("Move Down") { lab.movePost(effect, by: 1) }.disabled(lab.post.last == effect)
                    Button("Reset Knobs") { lab.resetParameters(of: effect.experiment) }
                    Divider()
                    Button("Remove", role: .destructive) {
                        lab.togglePost(effect)
                        lab.disabledPost.remove(effect)
                        if openPost == effect { openPost = nil }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .font(.caption)
            }
            if openPost == effect {
                LabKnobList(lab: lab, experiment: effect.experiment)
                    .padding(.leading, 22)
            }
        }
    }

    private var stageSummary: String {
        var parts = ["\(Int(lab.diameter)) pt", lab.darkStage ? "Dark" : "Light"]
        if lab.intensity != 0.5 { parts.append("Intensity \(String(format: "%.2f", lab.intensity))") }
        if lab.speed != 1 { parts.append(String(format: "%.1f×", lab.speed)) }
        if lab.fill != 1 { parts.append(String(format: "Fill %.2f", lab.fill)) }
        return parts.joined(separator: " · ")
    }

    private var stageSection: some View {
        LabRailSection("stage", "Stage", summary: stageSummary, defaultOpen: false) {
            LabSlider(title: "Intensity", value: $lab.intensity, range: 0...1, help: "What “more” means is per experiment — warp, glow, radius — but it always means more.")
            LabSlider(title: "Speed", value: $lab.speed, range: 0.1...3, format: "%.1f×", help: "Time multiplier. 1 is the experiment's designed pace.")
            LabSlider(title: "Size", value: $lab.diameter, range: 62...600, format: "%.0f pt", help: "Stage diameter.")
            LabSlider(title: "Fill", value: $lab.fill, range: 0...1.3, help: "Scales the experiment to fill the circle. 1 is edge to edge; past it crops.")
            checkboxRow("Dark stage", $lab.darkStage, help: "Dark is where these look best; light is where the tab bar usually is.")
            if !lab.experiment.usesPhoneCanvas {
                checkboxRow("Pod preview", $lab.showPod, help: "The experiment at 62 pt in the pod's glass, in the corner.")
                if lab.showPod {
                    checkboxRow("Fill the pod", $lab.podFill, help: "Edge to edge, rather than the ring's proportion inside the pod.")
                }
            }
        }
    }

    private var colourSection: some View {
        LabRailSection("colour", "Colour", summary: lab.palette.label + (lab.hueDrift != 0 ? String(format: " · %.0f°/s", lab.hueDrift) : "") + (lab.glyph.isEmpty ? "" : " · \(lab.glyph)"), defaultOpen: false) {
            HStack(spacing: 8) {
                Text("Palette").font(.callout).foregroundStyle(.secondary).frame(width: LabRailMetrics.labelWidth, alignment: .leading)
                Picker("", selection: $lab.palette) {
                    ForEach(LabPalette.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small)
                HStack(spacing: 3) {
                    ForEach(Array(lab.colors(config: config, at: 0).enumerated()), id: \.offset) { _, c in
                        RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 14, height: 14)
                    }
                }
                Spacer(minLength: 0)
            }
            .help("The Nexus animation's own colours, or a curated set — to judge an experiment in colours it wasn't designed around.")
            LabSlider(title: "Hue drift", value: $lab.hueDrift, range: -90...90, format: "%.0f°/s", help: "Rotates every colour's hue over time. The palette's relationships hold.")
            HStack(spacing: 8) {
                Text("Glyph").font(.callout).foregroundStyle(.secondary).frame(width: LabRailMetrics.labelWidth, alignment: .leading)
                TextField("SF Symbol", text: $lab.glyph)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
            }
            .help("An SF Symbol drawn inside. Orb, Refraction, Liquid and Sphere are built for it.")
        }
    }

    private var audioSummary: String {
        guard lab.audioReactive else { return "Off" }
        var parts = [lab.audioSource.label, String(format: "%.1f×", lab.audioSensitivity)]
        if lab.transcribe { parts.append("Transcript") }
        return parts.joined(separator: " · ")
    }

    private var audioSection: some View {
        LabRailSection("audio", "Audio", summary: audioSummary, defaultOpen: false) {
            checkboxRow("Audio reactive", $lab.audioReactive, help: "Feed the microphone into the experiment.")
            if lab.audioReactive {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Drives").font(.callout).foregroundStyle(.secondary)
                    Picker("", selection: $lab.audioSource) {
                        ForEach(LabAudioSource.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).controlSize(.small)
                }
                .help("Which signal the experiment's audio input carries.")
                LabSlider(title: "Sensitivity", value: $lab.audioSensitivity, range: 0.5...5, format: "%.1f×")
                LabSlider(title: "Attack", value: $lab.audioAttack, range: 0.005...0.3, format: "%.3f s", help: "How fast a rise is followed.")
                LabSlider(title: "Release", value: $lab.audioRelease, range: 0.05...2, format: "%.2f s", help: "How slowly a fall is followed. Long release is the ‘breathing’ look.")
                LabBandMeters(bands: bands)
                checkboxRow("Live transcript", $lab.transcribe, help: "Speech recognition on the mic — Bloom Field, the Transcript adornment and the Talk container show your words as you say them.")
                if let error = audio.transcriptError {
                    Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
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
            .help("A still of the stage at 2×, to the Desktop. Liquid Glass and RealityKit don't rasterise.")
            if let savedFrameMessage {
                Text(savedFrameMessage).font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    /// A checkbox on the rail's grid: indented past the label column, so
    /// it lines up with the sliders' controls.
    private func checkboxRow(_ title: String, _ isOn: Binding<Bool>, help: String) -> some View {
        HStack(spacing: 8) {
            Spacer().frame(width: LabRailMetrics.labelWidth)
            Toggle(title, isOn: isOn).font(.callout)
            Spacer(minLength: 0)
        }
        .help(help)
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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, i == 0 ? 0 : 6)
            }
            LabKnob(parameter: parameter, value: lab.binding(parameter, of: experiment))
        }
    }
}
