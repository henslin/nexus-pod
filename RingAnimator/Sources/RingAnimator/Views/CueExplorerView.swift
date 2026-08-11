import SwiftUI
import AppKit
import RingAnimatorCore

/// The Cue Library's cue list — one category-and-subcategory-grouped list,
/// used as the "content" column of the app's top-level three-column split
/// (see `ContentView`). Lives as its own view (rather than owning a
/// `NavigationSplitView` itself) so it can sit alongside `ContentView`'s
/// single top-level sidebar instead of stacking a second one underneath it.
struct CueListView: View {
    @ObservedObject var store: LEDCueStore
    @Binding var selectedCueID: String?
    @Binding var searchText: String

    var body: some View {
        List(selection: $selectedCueID) {
            ForEach(LEDCueLibrary.categories, id: \.self) { category in
                let groups = LEDCueLibrary.groupedBySubcategory(in: category)
                    .map { group in (subcategory: group.subcategory, cues: group.cues.filter { matches($0) }) }
                    .filter { !$0.cues.isEmpty }
                if !groups.isEmpty {
                    Section(category) {
                        ForEach(groups, id: \.subcategory) { group in
                            if let subcategory = group.subcategory {
                                Text(subcategory)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(group.cues) { cue in
                                CueRow(cue: cue, isModified: store.isModified(cue))
                                    .tag(cue.id)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, prompt: "Search cues")
        .toolbar {
            ToolbarItem {
                Button {
                    exportLibrary()
                } label: {
                    Label("Export Library…", systemImage: "square.and.arrow.up")
                }
                .help("Export the full cue library, with your tweaks applied, as JSON")
            }
            ToolbarItem {
                Button(role: .destructive) {
                    store.resetAll()
                } label: {
                    Label("Reset All", systemImage: "arrow.counterclockwise")
                }
                .help("Reset every cue back to its shipped default")
                .disabled(store.overrides.isEmpty)
            }
        }
    }

    private func matches(_ cue: LEDCue) -> Bool {
        searchText.isEmpty
            || cue.name.localizedCaseInsensitiveContains(searchText)
            || cue.specText.localizedCaseInsensitiveContains(searchText)
            || (cue.subcategory ?? "").localizedCaseInsensitiveContains(searchText)
    }

    private func exportLibrary() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ziris-led-cue-library.json"
        if panel.runModal() == .OK, let url = panel.url {
            try? store.exportSnapshotJSON().write(to: url)
        }
    }
}

private struct CueRow: View {
    let cue: LEDCue
    let isModified: Bool

    var body: some View {
        HStack {
            Text(cue.name)
            Spacer()
            if isModified {
                Circle().fill(Color.accentColor).frame(width: 6, height: 6)
            }
        }
    }
}

/// Detail pane: live preview, the original spec-sheet text for reference,
/// and an editable form. Every edit autosaves to `LEDCueStore` immediately —
/// there's no separate Save step, only Reset. Used as the "detail" column
/// when Cue Library is selected in `ContentView`.
struct CueDetailView: View {
    let cue: LEDCue
    @ObservedObject var store: LEDCueStore
    @State private var params: LEDCueParameters

    init(cue: LEDCue, store: LEDCueStore) {
        self.cue = cue
        self.store = store
        _params = State(initialValue: store.parameters(for: cue))
    }

    private var isModified: Bool { params != cue.defaultParameters }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                preview
                specReference
                form
            }
            .padding(24)
        }
        .onChange(of: params) { _, newValue in
            store.update(newValue, for: cue)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text([cue.category, cue.subcategory].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(cue.name).font(.title2.bold())
                if isModified {
                    Text("Tweaked")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                if isModified {
                    Button("Reset to Default") {
                        params = cue.defaultParameters
                    }
                    .ringGlassButtonStyle()
                }
            }
        }
    }

    private var preview: some View {
        HStack(spacing: 24) {
            LEDCuePreviewView(parameters: params, diameter: 120, lineWidth: 12)
                .frame(width: 160, height: 160)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(0.9)))
            VStack(alignment: .leading, spacing: 6) {
                Text(params.style.displayName).font(.headline)
                Text("Primary \(params.primaryColorHex) · Secondary \(params.secondaryColorHex)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var specReference: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Spec sheet reference").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(cue.specText)
                .font(.callout)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        }
    }

    private var loopsLabel: String {
        params.loops == 0 ? "Loops: ∞ (until cleared)" : "Loops: \(params.loops)"
    }

    private var form: some View {
        Form {
            Section("Pattern") {
                Picker("Style", selection: $params.style) {
                    ForEach(LEDPatternStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                LabeledSlider(title: "Speed", value: $params.speed, range: 0.1...4.0, format: "%.2fx")
                Stepper("Flash count: \(params.flashCount)", value: $params.flashCount, in: 0...10)
                LabeledSlider(title: "Hold", value: $params.holdSeconds, range: 0...6, format: "%.1fs")
                LabeledSlider(title: "Fade out", value: $params.fadeOutSeconds, range: 0...3, format: "%.1fs")
                Stepper(loopsLabel, value: $params.loops, in: 0...10)
            }

            if params.style == .continuousAnimation {
                Section {
                    Picker("Animation type", selection: $params.animationType) {
                        ForEach(RingAnimationType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    Text(params.animationType.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LabeledSlider(title: "Line width", value: $params.lineWidth, range: 2...16, format: "%.0f pt")

                    if params.animationType == .chasing {
                        Picker("Fill style", selection: $params.chasingFillStyle) {
                            ForEach(ChasingFillStyle.allCases) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                    }
                    if params.animationType == .chasing || params.animationType == .dualChase {
                        LabeledSlider(
                            title: params.animationType == .chasing && params.chasingFillStyle == .drawUndraw ? "Peak length" : "Trail length",
                            value: $params.trailFraction, range: 0.05...1.0, format: "%.2f"
                        )
                    }
                    if params.animationType == .alternating || params.animationType == .equalizer || params.animationType == .sparkle {
                        LabeledSlider(
                            title: params.animationType == .equalizer ? "Segment count" : params.animationType == .sparkle ? "Sparkle count" : "Diode count",
                            value: $params.diodeCount, range: 8...60, format: "%.0f"
                        )
                    }
                } header: {
                    Text("Continuous Animation")
                } footer: {
                    Text("Only used by the \"Continuous Animation (Nexus)\" style above — the exact same knobs as Nexus's own Animation section, so anything designed there reproduces here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("Easing", selection: $params.easingStyle) {
                    ForEach(EasingStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                if params.easingStyle == .spring {
                    LabeledSlider(title: "Spring bounce", value: $params.springBounce, range: 0...1, format: "%.2f")
                }

                Toggle("Scale pulse (breathing)", isOn: $params.scalePulseEnabled)
                if params.scalePulseEnabled {
                    LabeledSlider(title: "Amount", value: $params.scalePulseAmount, range: 0.02...0.4, format: "%.2f")
                    LabeledSlider(title: "Speed", value: $params.scalePulseSpeed, range: 0.1...3.0, format: "%.1fx")
                }

                Toggle("Color cycling (hue shift)", isOn: $params.hueShiftEnabled)
                if params.hueShiftEnabled {
                    LabeledSlider(title: "Speed", value: $params.hueShiftSpeed, range: 0.02...1.0, format: "%.2fx")
                }
            } header: {
                Text("Motion Effects")
            } footer: {
                Text("Same effects as Nexus — layer on top of the pattern style above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Glow & Blend") {
                Toggle("Vibrancy", isOn: $params.vibrancyEnabled)
                if params.vibrancyEnabled {
                    LabeledSlider(title: "Amount", value: $params.vibrancyAmount, range: 1.0...2.5, format: "%.2fx")
                }

                Toggle("Glow", isOn: $params.glowEnabled)
                if params.glowEnabled {
                    LabeledSlider(title: "Glow radius", value: $params.glowRadius, range: 2...24, format: "%.0f pt")
                }

                LabeledSlider(title: "Blur", value: $params.blurRadius, range: 0...12, format: "%.0f pt")
                Picker("Blend mode", selection: $params.blendMode) {
                    ForEach(RingBlendMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                Toggle("Chromatic aberration", isOn: $params.chromaticAberrationEnabled)
                if params.chromaticAberrationEnabled {
                    LabeledSlider(title: "Amount", value: $params.chromaticAberrationAmount, range: 0...30, format: "%.0f pt")
                }
            }

            Section {
                Toggle("Particles", isOn: $params.particlesEnabled)
                if params.particlesEnabled {
                    Picker("Emitter shape", selection: $params.particleEmitterShape) {
                        ForEach(ParticleEmitterShape.allCases) { shape in
                            Text(shape.rawValue).tag(shape)
                        }
                    }
                    Picker("Emitter mode", selection: $params.particleEmitterMode) {
                        ForEach(ParticleEmitterMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    LabeledSlider(title: "Emitter size", value: $params.particleEmitterSizeMultiplier, range: 0.1...3, format: "%.1fx")
                    Picker("Render mode", selection: $params.particleRenderMode) {
                        ForEach(ParticleRenderMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }

                    LabeledSlider(title: "Birth rate", value: $params.particleBirthRate, range: 0...40, format: "%.0f/s")
                    LabeledSlider(title: "Lifetime", value: $params.particleLifetime, range: 0.2...4, format: "%.1fs")
                    LabeledSlider(title: "Lifetime range", value: $params.particleLifetimeRange, range: 0...2, format: "%.1fs")
                    LabeledSlider(title: "Velocity", value: $params.particleVelocity, range: 0...150, format: "%.0f pt/s")
                    LabeledSlider(title: "Velocity range", value: $params.particleVelocityRange, range: 0...80, format: "%.0f pt/s")
                    LabeledSlider(title: "Emission longitude", value: $params.particleEmissionLongitude, range: 0...360, format: "%.0f°")
                    LabeledSlider(title: "Emission spread", value: $params.particleEmissionSpread, range: 0...360, format: "%.0f°")
                    LabeledSlider(title: "X acceleration", value: $params.particleXAcceleration, range: -100...100, format: "%.0f pt/s²")
                    LabeledSlider(title: "Y acceleration", value: $params.particleYAcceleration, range: -100...100, format: "%.0f pt/s²")
                    LabeledSlider(title: "Spin", value: $params.particleSpin, range: -6...6, format: "%.1f rad/s")
                    LabeledSlider(title: "Spin range", value: $params.particleSpinRange, range: 0...6, format: "%.1f rad/s")
                    LabeledSlider(title: "Scale", value: $params.particleScale, range: 1...10, format: "%.0f pt")
                    LabeledSlider(title: "Scale range", value: $params.particleScaleRange, range: 0...5, format: "%.0f pt")

                    Toggle("Pulse birth rate", isOn: $params.particlePulseEnabled)
                    if params.particlePulseEnabled {
                        LabeledSlider(title: "Pulse period", value: $params.particlePulsePeriod, range: 0.1...3, format: "%.1fs")
                    }
                    LabeledSlider(title: "Blur", value: $params.particleBlurRadius, range: 0...20, format: "%.0f pt")
                }
            } header: {
                Text("Particles")
            }

            Section("Color") {
                ColorPicker("Primary", selection: Binding(
                    get: { Color(hex: params.primaryColorHex) },
                    set: { params.primaryColorHex = $0.hexString }
                ))
                Text(params.primaryColorHex).font(.caption).foregroundStyle(.secondary)
                ColorPicker("Secondary", selection: Binding(
                    get: { Color(hex: params.secondaryColorHex) },
                    set: { params.secondaryColorHex = $0.hexString }
                ))
                Text(params.secondaryColorHex).font(.caption).foregroundStyle(.secondary)
            }

            Section("Notes") {
                TextEditor(text: $params.notes)
                    .frame(minHeight: 60)
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    var body: some View {
        HStack {
            Text(title)
            Slider(value: $value, in: range)
            Text(String(format: format, value))
                .font(.caption.monospacedDigit())
                .frame(width: 56, alignment: .trailing)
        }
    }
}
