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

    /// Which category sections are open.
    ///
    /// Starts with just the one holding the current selection, because the
    /// library is 64 cues and every visible row now renders a live
    /// animating preview — opening all of them at once is both a wall of
    /// motion to read and a lot of `TimelineView`s driving at once.
    /// Onboarding alone is 23.
    @State private var expandedCategories: Set<String> = []

    /// Which subcategories are open, keyed `category/subcategory`.
    ///
    /// Composite key because subcategory names aren't unique across
    /// categories — keying on the bare name would tie unrelated groups in
    /// different categories together.
    @State private var expandedSubcategories: Set<String> = []

    var body: some View {
        ListColumn(search: $searchText, searchPrompt: "Search cues") {
            List(selection: $selectedCueID) {
                ForEach(LEDCueLibrary.categories, id: \.self) { category in
                    let groups = LEDCueLibrary.groupedBySubcategory(in: category)
                        .map { group in (subcategory: group.subcategory, cues: group.cues.filter { matches($0) }) }
                        .filter { !$0.cues.isEmpty }
                    if !groups.isEmpty {
                        Section(isExpanded: expansion(for: category)) {
                            ForEach(groups, id: \.subcategory) { group in
                                if let subcategory = group.subcategory {
                                    let isExpanded = subExpansion(category: category, subcategory: subcategory)
                                    DisclosureGroup(isExpanded: isExpanded) {
                                        cueRows(group.cues)
                                    } label: {
                                        // Deliberately between the two levels
                                        // around it: smaller and dimmer than
                                        // the category header so the hierarchy
                                        // still reads, but not the tertiary
                                        // caption2 this used to be — that was
                                        // unclickably small once it became a
                                        // control rather than a caption. Same
                                        // full-width hit target as the header
                                        // above, for the same reason.
                                        Text(subcategory.uppercased())
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .padding(.vertical, 3)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                            // macOS `DisclosureGroup` only makes
                                            // the chevron itself a toggle target
                                            // — clicking the label does nothing,
                                            // which is the same too-small hit
                                            // target the category headers had,
                                            // one level down. The `Section`
                                            // headers above toggle on their
                                            // whole row for free; this makes
                                            // these match.
                                            .onTapGesture { isExpanded.wrappedValue.toggle() }
                                    }
                                } else {
                                    // Categories whose cues aren't grouped at
                                    // all — nothing to disclose, so the rows
                                    // sit directly under the category.
                                    cueRows(group.cues)
                                }
                            }
                        } header: {
                            // A custom header rather than `Section(category,
                            // isExpanded:)`'s automatic one.
                            //
                            // The default renders category names in the small,
                            // dim, secondary type a section header normally
                            // wants — correct when a header labels visible
                            // content, wrong here. With every section closed
                            // these headers *are* the navigation, and label
                            // styling doesn't advertise that they're the thing
                            // to click. Their height was never really the
                            // problem (~27pt, about a standard sidebar row);
                            // they just didn't read as targets.
                            //
                            // `contentShape` makes the whole width clickable
                            // rather than only the glyph-width of the text.
                            Text(category)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .onAppear {
                // Open whichever category holds the current selection, so the
                // list doesn't start as seven closed headers with nothing to
                // look at.
                if expandedCategories.isEmpty,
                   let selectedCueID,
                   let cue = LEDCueLibrary.cue(id: selectedCueID) {
                    expandedCategories.insert(cue.category)
                    // And the subcategory too, or opening the category reveals
                    // nothing but another closed header and the selected cue
                    // still isn't visible.
                    if let subcategory = cue.subcategory {
                        expandedSubcategories.insert("\(cue.category)/\(subcategory)")
                    }
                }
            }

        } actions: {
            Button {
                exportLibrary()
            } label: {
                Label("Export Library…", systemImage: "square.and.arrow.up")
            }
            .help("Export the full cue library, with your tweaks applied, as JSON")

            Button(role: .destructive) {
                store.resetAll()
            } label: {
                Label("Reset All", systemImage: "arrow.counterclockwise")
            }
            .help("Reset every cue back to its shipped default")
            .disabled(store.overrides.isEmpty)
        }
    }

    @ViewBuilder
    private func cueRows(_ cues: [LEDCue]) -> some View {
        ForEach(cues) { cue in
            CueRow(
                cue: cue,
                parameters: store.parameters(for: cue),
                isModified: store.isModified(cue)
            )
            .tag(cue.id)
        }
    }

    /// Binding for one subcategory's disclosure state. Same
    /// search-overrides-everything rule as `expansion(for:)`.
    private func subExpansion(category: String, subcategory: String) -> Binding<Bool> {
        let key = "\(category)/\(subcategory)"
        return Binding(
            get: { !searchText.isEmpty || expandedSubcategories.contains(key) },
            set: { isExpanded in
                if isExpanded {
                    expandedSubcategories.insert(key)
                } else {
                    expandedSubcategories.remove(key)
                }
            }
        )
    }

    /// Binding for one category's disclosure state.
    ///
    /// While a search is active every section reads as expanded regardless
    /// of what's stored — a filtered-out section is already hidden, and a
    /// section that matched but stayed collapsed would look like the
    /// search found nothing. Toggling during a search still records the
    /// intent, so closing the search returns the list to how it was left.
    private func expansion(for category: String) -> Binding<Bool> {
        Binding(
            get: { !searchText.isEmpty || expandedCategories.contains(category) },
            set: { isExpanded in
                if isExpanded {
                    expandedCategories.insert(category)
                } else {
                    expandedCategories.remove(category)
                }
            }
        )
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
    /// The cue's *effective* parameters — `store.parameters(for:)`, so the
    /// thumbnail shows your tweaks rather than the shipped defaults.
    let parameters: LEDCueParameters
    let isModified: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Same 22-in-28 thumbnail Saved Animations and Use Cases rows
            // use. `LEDCuePreviewView` rather than `RingView` because a cue
            // is `LEDCueParameters`, not a `RingPreset` — it renders the
            // spec-sheet styles directly and hands the continuous ones to
            // `RingView` itself.
            //
            // `lineWidth` has to be given explicitly: it defaults to 12,
            // which is most of a 22pt ring's radius and renders as a solid
            // blob at this size.
            LEDCuePreviewView(parameters: parameters, diameter: 22, lineWidth: 3, frameRate: RingView.thumbnailFrameRate)
                .frame(width: 28, height: 28)
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
    /// Shared with every other section — see `StageState`.
    @ObservedObject var stageState: StageState
    @State private var params: LEDCueParameters
    @State private var expanded: [String: Bool]
    /// The cue, in the form every preview surface takes — see `previewPane`.
    @StateObject private var stageConfig = RingConfig()

    init(cue: LEDCue, store: LEDCueStore, stageState: StageState) {
        self.cue = cue
        self.store = store
        self.stageState = stageState
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

    /// Left/center pane: cue name, the shared `RingStage`, and the
    /// spec-sheet reference text.
    ///
    /// The preview used to be a 200pt ring in a scrolling column — the
    /// Cue Library's own smaller version of what Nexus had. It's the same
    /// canvas now: phone mockup, pinch to zoom, floating Large Preview,
    /// light/dark toggle. The spec sheet moves to a fixed strip along the
    /// bottom, where Nexus puts its timeline, rather than scrolling with a
    /// preview that no longer scrolls.
    private var previewPane: some View {
        // Exactly Nexus's shape: the stage fills the pane, and a single
        // strip sits under it. The cue's name used to be a header block
        // *above* the stage, which made this the one section whose canvas
        // was shorter than the others for no reason anyone could see — the
        // name lives in the window title now (see `ContentView`).
        VStack(spacing: 0) {
            RingStage(config: stageConfig, state: stageState)
            Divider()
            ScrollView {
                specReference
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
            }
            .frame(height: 150)
        }
        // The stage speaks `RingConfig`, so the cue is converted into one —
        // by the same `apply(to:)` `LEDCuePreviewView` has always used, not
        // a second conversion written to look like it. Held as a
        // `@StateObject` and re-synced rather than rebuilt per change:
        // `RingConfig.init()` does a synchronous Keychain read and spins up
        // a `VoiceConversationController`, both wasted work if repeated
        // every time a slider moves.
        .onAppear { params.apply(to: stageConfig) }
        .onChange(of: params) { _, newValue in newValue.apply(to: stageConfig) }
    }

    /// Right pane: every `GlassSectionCard` from `controls`, in its own
    /// scroll view — the Cue Library's equivalent of `ControlsView.body`.
    private var controlsPanel: some View {
        VStack(spacing: 0) {
            // What used to be the header above the stage. The breadcrumb
            // and the Tweaked badge say what this cue is and whether you've
            // changed it, and Reset to Default undoes those changes — all
            // of which is about the parameters below, not about the canvas
            // it used to sit on top of.
            detailHeader
            Divider()
            ScrollView {
                controls
                    .padding(16)
            }
        }
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text([cue.category, cue.subcategory].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isModified {
                HStack(spacing: 8) {
                    Text("Tweaked")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        .foregroundStyle(Color.accentColor)
                    Spacer(minLength: 0)
                    Button("Reset to Default") {
                        params = cue.defaultParameters
                    }
                    .ringGlassButtonStyle()
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
                    if params.animationType == .multiChase {
                        LabeledSlider(title: "Comet Length", value: $params.trailFraction, range: 0.05...1.0, format: "%.2f")
                    }

                    // Diode Mode and its shape controls, mirroring
                    // `AnimationSection`. Every one of these is Optional on
                    // `LEDCueParameters` — they postdate the saved cue JSON
                    // — so each binding supplies the same default
                    // `RingConfig` uses.
                    Toggle("Diode Mode", isOn: optional($params.diodeModeEnabled, default: false))
                    if params.diodeModeEnabled == true
                        || params.animationType == .alternating
                        || params.animationType == .sparkle
                        || params.animationType == .multiChase {
                        Picker("Diode Shape", selection: optional($params.diodeShape, default: .round)) {
                            ForEach(DiodeShape.allCases) { shape in
                                Text(shape.rawValue).tag(shape)
                            }
                        }
                        .pickerStyle(.menu)

                        if (params.diodeShape ?? .round).dividesTheRing {
                            LabeledSlider(title: "Segment Gap", value: optional($params.diodeGap, default: 0.12), range: 0...0.6, format: "%.2f")
                        } else {
                            LabeledSlider(title: "Diode Size", value: optional($params.diodeScale, default: 1.0), range: 0.4...3.0, format: "%.2fx")
                        }
                    }

                    if params.animationType == .alternating || params.animationType == .equalizer
                        || params.animationType == .sparkle || params.animationType == .multiChase
                        || params.diodeModeEnabled == true {
                        LabeledSlider(
                            title: params.animationType == .equalizer ? "Segment Count" : params.animationType == .sparkle ? "Sparkle Count" : "Diode Count",
                            value: $params.diodeCount, range: 8...60, format: "%.0f"
                        )
                    }

                    if params.animationType == .multiChase || params.diodeModeEnabled == true {
                        Picker("Blink", selection: optional($params.blinkPattern, default: .steady)) {
                            ForEach(BlinkPattern.allCases) { pattern in
                                Text(pattern.rawValue).tag(pattern)
                            }
                        }
                        .pickerStyle(.menu)
                        if (params.blinkPattern ?? .steady) != .steady {
                            LabeledSlider(title: "Blink Rate", value: optional($params.blinkRate, default: 2.0), range: 0.2...12, format: "%.1f/s")
                        }
                    }

                    if params.animationType == .bloom {
                        LabeledSlider(title: "Patches", value: optional($params.bloomCount, default: 6), range: 2...14, format: "%.0f")
                        LabeledSlider(title: "Average Size", value: $params.trailFraction, range: 0.05...0.5, format: "%.2f")
                        LabeledSlider(title: "Base Brightness", value: optional($params.bloomBase, default: 0.6), range: 0...1, format: "%.2f")
                        LabeledSlider(title: "Softness", value: optional($params.bloomSoftness, default: 0.15), range: 0...1, format: "%.2f")
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


/// Unwraps an `Optional` parameter into a plain `Binding` with a default.
///
/// Everything added to `LEDCueParameters` after the cue library shipped is
/// Optional — synthesized `Decodable` won't fill in a key that saved JSON
/// doesn't have, so those fields can't be plain defaulted properties. The
/// editors want ordinary bindings, and the default supplied here is always
/// the matching `RingConfig` default, so an untouched cue behaves exactly
/// as one that never had the field.
private func optional<T>(_ source: Binding<T?>, default fallback: T) -> Binding<T> {
    Binding(
        get: { source.wrappedValue ?? fallback },
        set: { source.wrappedValue = $0 }
    )
}
