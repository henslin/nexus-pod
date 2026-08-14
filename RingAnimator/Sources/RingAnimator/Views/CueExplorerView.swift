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
    @State private var expanded: [String: Bool]

    init(cue: LEDCue, store: LEDCueStore) {
        self.cue = cue
        self.store = store
        let initialParams = store.parameters(for: cue)
        _params = State(initialValue: initialParams)
        // Same defaults as Nexus's own Controls panel (`ControlsView.init`):
        // the core "what does this cue look like" sections start open,
        // Particles opens expanded only if this cue already uses them.
        // Playback (Hold/Fade Out/Loops) starts open too, unlike Nexus's
        // equivalent card — those fields are always in effect for a cue
        // (there's no "Sequence Playback" enable switch here the way
        // `RingConfig` has one), so there's no reason to hide them by default.
        _expanded = State(initialValue: [
            "color": true,
            "animation": true,
            "shape": true,
            "motion": true,
            "glow": true,
            "particles": initialParams.particlesEnabled,
            "playback": true,
            "notes": !initialParams.notes.isEmpty
        ])
    }

    private var isModified: Bool { params != cue.defaultParameters }

    /// Same `HSplitView` shape as Nexus's own detail pane
    /// (`ContentView.detail`'s `.ringDesigner` case): the preview stands on
    /// its own in the wider left/center pane — the Cue Library's equivalent
    /// of Nexus's iPhone mockup as "the thing you're looking at" — while
    /// every control lives in a `ControlsView`-style panel pinned to the
    /// right edge, instead of both being stacked in one long scrolling
    /// column above the controls.
    var body: some View {
        HSplitView {
            previewPane
                .frame(minWidth: 420, idealWidth: 640)
            controlsPanel
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 340)
        }
        .onChange(of: params) { _, newValue in
            store.update(newValue, for: cue)
        }
    }

    /// Left/center pane: cue name, the live preview (now the pane's own
    /// centerpiece rather than a small thumbnail squeezed above the
    /// controls), and the spec-sheet reference text.
    private var previewPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                centeredPreview
                specReference
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Right pane: every `GlassSectionCard` from `controls`, in its own
    /// scroll view — the Cue Library's equivalent of `ControlsView.body`.
    private var controlsPanel: some View {
        ScrollView {
            controls
                .padding(16)
        }
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

    /// Bigger and horizontally centered now that it has a whole pane to
    /// itself instead of sharing a row with the style/color caption —
    /// same "the animation gets to be the centerpiece" reasoning as
    /// Nexus's phone mockup/large preview.
    private var centeredPreview: some View {
        VStack(spacing: 12) {
            LargePreviewCard(diameter: 200) {
                LEDCuePreviewView(parameters: params, diameter: 200, lineWidth: 14)
            }
            VStack(spacing: 4) {
                Text(params.style.displayName).font(.headline)
                Text("Primary \(params.primaryColorHex) · Secondary \(params.secondaryColorHex)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var specReference: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Spec Sheet Reference").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
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

    /// Same collapsible Liquid Glass cards as Nexus's own Controls panel
    /// (`ControlsView`/`GlassSectionCard`, in `RingAnimatorCore`) instead of
    /// a plain `Form`, and the same section grouping/naming: Color,
    /// Animation, Shape, Motion Effects, Glow & Blend, Particles, Playback —
    /// in that order, mirroring `ControlsView.body` exactly. Two deliberate
    /// differences from Nexus, both driven by how `LEDCueParameters` differs
    /// from `RingConfig`, not by inconsistency:
    /// - Easing/Spring Bounce live in "Animation" here (unconditionally,
    ///   like Nexus), but the Type/Fill Style/Trail-Peak Length/Diode-
    ///   Segment-Sparkle Count knobs only appear for `.continuousAnimation`
    ///   — `LEDCuePreviewView` only reads them for that one style, unlike
    ///   Nexus where `RingConfig.animationType` always drives the base ring.
    /// - "Playback" (Hold/Fade Out/Loops) has no master toggle — every cue's
    ///   hold/fade/loop envelope is always in effect, unlike Nexus's opt-in
    ///   "Sequence Playback".
    /// "Notes" is Cue-Library-specific, appended after Playback since Nexus
    /// has nothing to match it against.
    private var controls: some View {
        VStack(spacing: 12) {
            card("color", "Color", "paintpalette") {
                ColorPicker("Primary", selection: Binding(
                    get: { Color(hex: params.primaryColorHex) },
                    set: { params.primaryColorHex = $0.hexString }
                ))
                Text(params.primaryColorHex).font(.caption).foregroundStyle(.secondary)
                ApprovedColorSwatchGrid(selectedHex: params.primaryColorHex) { params.primaryColorHex = $0.hexString }

                ColorPicker("Secondary", selection: Binding(
                    get: { Color(hex: params.secondaryColorHex) },
                    set: { params.secondaryColorHex = $0.hexString }
                ))
                Text(params.secondaryColorHex).font(.caption).foregroundStyle(.secondary)
                ApprovedColorSwatchGrid(selectedHex: params.secondaryColorHex) { params.secondaryColorHex = $0.hexString }
            }

            card("animation", "Animation", "play.circle") {
                Picker("Pattern Style", selection: $params.style) {
                    ForEach(LEDPatternStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                if params.style == .flash || params.style == .quickFlash {
                    Stepper("Flash Count: \(params.flashCount)", value: $params.flashCount, in: 0...10)
                }
                LabeledSlider(title: "Speed", value: $params.speed, range: 0.1...4.0, format: "%.2fx")

                Picker("Easing", selection: $params.easingStyle) {
                    ForEach(EasingStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                Text(params.easingStyle.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if params.easingStyle == .spring {
                    LabeledSlider(title: "Spring Bounce", value: $params.springBounce, range: 0...1, format: "%.2f")
                }

                if params.style == .continuousAnimation {
                    Picker("Type", selection: $params.animationType) {
                        ForEach(RingAnimationType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    Text(params.animationType.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if params.animationType == .chasing {
                        Picker("Fill Style", selection: $params.chasingFillStyle) {
                            ForEach(ChasingFillStyle.allCases) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                        if params.chasingFillStyle == .drawUndraw {
                            Text("Grows to the peak length, then shrinks back to a point — same clockwise sweep the whole time, one pulse per lap. 1.00 draws a full circle before undrawing it.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if params.animationType == .chasing || params.animationType == .dualChase {
                        LabeledSlider(
                            title: params.animationType == .chasing && params.chasingFillStyle == .drawUndraw ? "Peak Length" : "Trail Length",
                            value: $params.trailFraction, range: 0.05...1.0, format: "%.2f"
                        )
                    }
                    if params.animationType == .alternating || params.animationType == .equalizer || params.animationType == .sparkle {
                        LabeledSlider(
                            title: params.animationType == .equalizer ? "Segment Count" : params.animationType == .sparkle ? "Sparkle Count" : "Diode Count",
                            value: $params.diodeCount, range: 8...60, format: "%.0f"
                        )
                    }
                    Text("Only used by the \"Continuous Animation (Nexus)\" style above — the exact same knobs as Nexus's own Animation section, so anything designed there reproduces here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            card("shape", "Shape", "circle.dashed") {
                LabeledSlider(title: "Line Width", value: $params.lineWidth, range: 2...16, format: "%.0f pt")
            }

            card("motion", "Motion Effects", "arrow.triangle.2.circlepath",
                 footer: "Layer these on top of any style above.") {
                Toggle("Scale Pulse (Breathing)", isOn: $params.scalePulseEnabled)
                if params.scalePulseEnabled {
                    LabeledSlider(title: "Amount", value: $params.scalePulseAmount, range: 0.02...0.4, format: "%.2f")
                    LabeledSlider(title: "Speed", value: $params.scalePulseSpeed, range: 0.1...3.0, format: "%.1fx")
                }

                Toggle("Color Cycling (Hue Shift)", isOn: $params.hueShiftEnabled)
                if params.hueShiftEnabled {
                    LabeledSlider(title: "Speed", value: $params.hueShiftSpeed, range: 0.02...1.0, format: "%.2fx")
                }
            }

            card("glow", "Glow & Blend", "sun.max") {
                Toggle("Vibrancy", isOn: $params.vibrancyEnabled)
                if params.vibrancyEnabled {
                    LabeledSlider(title: "Amount", value: $params.vibrancyAmount, range: 1.0...2.5, format: "%.2fx")
                }

                Toggle("Glow", isOn: $params.glowEnabled)
                if params.glowEnabled {
                    LabeledSlider(title: "Glow Radius", value: $params.glowRadius, range: 2...24, format: "%.0f pt")
                }

                LabeledSlider(title: "Blur", value: $params.blurRadius, range: 0...12, format: "%.0f pt")
                Picker("Blend Mode", selection: $params.blendMode) {
                    ForEach(RingBlendMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                Toggle("Chromatic Aberration", isOn: $params.chromaticAberrationEnabled)
                if params.chromaticAberrationEnabled {
                    LabeledSlider(title: "Amount", value: $params.chromaticAberrationAmount, range: 0...30, format: "%.0f pt")
                }
            }

            card("particles", "Particles", "sparkles",
                 footer: "Raw CAEmitterLayer/CAEmitterCell controls — the same particle system UIKit/AppKit apps use.",
                 masterToggle: $params.particlesEnabled) {
                Toggle("Particles", isOn: $params.particlesEnabled)
                if params.particlesEnabled {
                    GroupCaption("Emission")
                    Picker("Emitter Shape", selection: $params.particleEmitterShape) {
                        ForEach(ParticleEmitterShape.allCases) { shape in
                            Text(shape.rawValue).tag(shape)
                        }
                    }
                    Picker("Emitter Mode", selection: $params.particleEmitterMode) {
                        ForEach(ParticleEmitterMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    LabeledSlider(title: "Emitter Size", value: $params.particleEmitterSizeMultiplier, range: 0.1...3, format: "%.1fx")
                    Picker("Render Mode", selection: $params.particleRenderMode) {
                        ForEach(ParticleRenderMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    LabeledSlider(title: "Birth Rate", value: $params.particleBirthRate, range: 0...40, format: "%.0f/s")
                    Toggle("Pulse Birth Rate", isOn: $params.particlePulseEnabled)
                    if params.particlePulseEnabled {
                        LabeledSlider(title: "Pulse Period", value: $params.particlePulsePeriod, range: 0.1...3, format: "%.1fs")
                    }
                    LabeledSlider(title: "Emission Longitude", value: $params.particleEmissionLongitude, range: 0...360, format: "%.0f°")
                    LabeledSlider(title: "Emission Spread", value: $params.particleEmissionSpread, range: 0...360, format: "%.0f°")

                    GroupCaption("Motion")
                    LabeledSlider(title: "Lifetime", value: $params.particleLifetime, range: 0.2...4, format: "%.1fs")
                    LabeledSlider(title: "Lifetime Range", value: $params.particleLifetimeRange, range: 0...2, format: "%.1fs")
                    LabeledSlider(title: "Velocity", value: $params.particleVelocity, range: 0...150, format: "%.0f pt/s")
                    LabeledSlider(title: "Velocity Range", value: $params.particleVelocityRange, range: 0...80, format: "%.0f pt/s")
                    LabeledSlider(title: "X Acceleration", value: $params.particleXAcceleration, range: -100...100, format: "%.0f pt/s²")
                    LabeledSlider(title: "Y Acceleration", value: $params.particleYAcceleration, range: -100...100, format: "%.0f pt/s²")
                    LabeledSlider(title: "Spin", value: $params.particleSpin, range: -6...6, format: "%.1f rad/s")
                    LabeledSlider(title: "Spin Range", value: $params.particleSpinRange, range: 0...6, format: "%.1f rad/s")

                    GroupCaption("Appearance")
                    LabeledSlider(title: "Scale", value: $params.particleScale, range: 1...10, format: "%.0f pt")
                    LabeledSlider(title: "Scale Range", value: $params.particleScaleRange, range: 0...5, format: "%.0f pt")
                    LabeledSlider(title: "Blur", value: $params.particleBlurRadius, range: 0...20, format: "%.0f pt")
                }
            }

            card("playback", "Playback", "repeat",
                 footer: "Unlike Nexus's optional Sequence Playback, every cue always plays this hold/fade/loop envelope — there's no separate on/off.") {
                LabeledSlider(title: "Hold", value: $params.holdSeconds, range: 0...6, format: "%.1fs")
                LabeledSlider(title: "Fade Out", value: $params.fadeOutSeconds, range: 0...3, format: "%.1fs")
                Stepper(loopsLabel, value: $params.loops, in: 0...10)
            }

            card("notes", "Notes", "note.text") {
                TextEditor(text: $params.notes)
                    .frame(minHeight: 60)
                    .font(.callout)
            }
        }
    }

    /// Binds a card's `isExpanded` into `expanded` keyed by `id` — same
    /// pattern as `ControlsView.card(...)`, duplicated rather than shared
    /// since the two views' section lists/content differ enough that a
    /// shared data-driven helper would be more indirection than it's worth.
    @ViewBuilder
    private func card<Content: View>(
        _ id: String,
        _ title: String,
        _ systemImage: String,
        footer: String? = nil,
        masterToggle: Binding<Bool>? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        GlassSectionCard(
            title: title,
            systemImage: systemImage,
            footer: footer,
            masterToggle: masterToggle,
            isExpanded: Binding(
                get: { expanded[id, default: true] },
                set: { expanded[id] = $0 }
            ),
            content: content
        )
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
