import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#elseif os(iOS)
import PhotosUI
#endif

/// The actual *content* of every settings section — pulled out of
/// `ControlsView` so it's shared, not duplicated, between the Mac app's
/// single long scrolling `Form` (`ControlsView` itself) and the iOS app's
/// drill-down menu (`RingSettingsMenu`, one screen per section). Each of
/// these is meant to sit directly inside a `Section { ... }` or a
/// standalone `Form { ... }` — they don't wrap themselves in either, so
/// the container decides the presentation.

// MARK: - Animation

struct AnimationSection: View {
    @ObservedObject var config: RingConfig

    /// Everything this picker offers, in declaration order — grouped into
    /// basic vs multi-phase by `body` below.
    private var selectableStyles: [LEDPatternStyle] {
        LEDPatternStyle.allCases.filter {
            ![.continuousAnimation, .earConOnly, .notApplicable, .voiceAssistantColor, .custom].contains($0)
        }
    }

    var body: some View {
        Picker("Pattern Style", selection: $config.patternStyle) {
            Text("Continuous").tag(LEDPatternStyle?.none)
            // Excludes a few Cue Library-only styles that don't make sense
            // as a live override on the ring you're actually looking at:
            // `.earConOnly`/`.notApplicable` describe cues with no LED
            // behavior at all, `.voiceAssistantColor` defers to a platform
            // color this app doesn't own, and `.custom` only means anything
            // alongside a cue's free-text `notes` field, which this picker
            // has no home for. All four stay selectable from the Cue
            // Library's own "Style" picker (`CueExplorerView`), where they
            // describe a specific spec-sheet row rather than override the
            // live preview.
            // Split so the single-behavior styles read as the default way
            // to build something and the canned multi-phase ones read as
            // what they are. Anything in the second group can be built out
            // of the first plus timeline steps — a composite's hold and
            // fade are hidden parameters, where a step's are visible and
            // editable.
            Section("Basic") {
                ForEach(selectableStyles.filter { !$0.isComposite }) { style in
                    Text(style.displayName).tag(LEDPatternStyle?.some(style))
                }
            }
            Section("Multi-phase (Cue Library)") {
                ForEach(selectableStyles.filter(\.isComposite)) { style in
                    Text(style.displayName).tag(LEDPatternStyle?.some(style))
                }
            }
        }
        .pickerStyle(.menu)
        Text("A single spec-sheet behavior (Spin, Pulse, Flash, Ripple, ...) instead of a continuous loop — overrides Animation Type below when set. The multi-phase entries bake in their own hold and fade; to control those yourself, pick a basic style and sequence it on the timeline.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        if config.patternStyle == .flash || config.patternStyle == .quickFlash {
            Stepper("Flash Count: \(config.flashCount)", value: $config.flashCount, in: 1...10)
        }

        Picker("Type", selection: $config.animationType) {
            ForEach(RingAnimationType.allCases) { type in
                Text(type.rawValue).tag(type)
            }
        }
        .pickerStyle(.menu)
        .disabled(config.patternStyle != nil)

        // `fixedSize(horizontal: false, vertical: true)` on every caption
        // below: take the width you're given and grow downward, rather than
        // claiming a single-line ideal width. Harmless in a plain stack,
        // and it keeps prose honest if these ever sit in a narrower
        // container again.
        Text(config.animationType.summary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        LabeledSlider(title: "Speed", value: $config.speed, range: 0.1...3.0, format: "%.1fx")

        if config.animationType == .chasing {
            Picker("Fill Style", selection: $config.chasingFillStyle) {
                ForEach(ChasingFillStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            if config.chasingFillStyle == .drawUndraw {
                Text("Grows to the peak length, then shrinks back to a point — same clockwise sweep the whole time, one pulse per lap. 1.00 draws a full circle before undrawing it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if config.animationType == .chasing || config.animationType == .dualChase {
            LabeledSlider(
                title: config.animationType == .chasing && config.chasingFillStyle == .drawUndraw ? "Peak Length" : "Trail Length",
                value: $config.trailFraction, range: 0.05...1.0, format: "%.2f"
            )
        }
        // Diode mode turns every animation into a fixed ring of pixels,
        // so the diode controls below apply to all of them once it's on —
        // not just to the types that were already diode-based.
        Toggle("Diode Mode", isOn: $config.diodeModeEnabled)
        Text(config.diodeModeEnabled
             ? "Diodes stay in place and only change brightness and color, the way addressable LED hardware works."
             : "Render any animation as a fixed ring of diodes instead of moving arcs and gradients.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        if config.diodeModeEnabled || config.animationType == .alternating
            || config.animationType == .sparkle || config.animationType == .multiChase {
            Picker("Diode Shape", selection: $config.diodeShape) {
                ForEach(DiodeShape.allCases) { shape in
                    Text(shape.rawValue).tag(shape)
                }
            }
            .pickerStyle(.menu)

            Text(config.diodeShape.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if config.diodeModeEnabled {
                LabeledSlider(title: "Floor", value: $config.diodeFloor, range: 0...1, format: "%.2f")
                Text("Minimum brightness every diode holds. Lifts and compresses the range rather than clipping the low end.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LabeledSlider(title: "Firmware Tick", value: $config.firmwareTickMs, range: 0...200, format: "%.0f ms")
                Text(config.firmwareTickMs > 0
                     ? "Rendering is snapped to this tick, so the preview shows what hardware updating at that rate can actually produce."
                     : "0 renders continuously. Set a tick to preview at a real driver's update rate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker("Diode Color", selection: $config.diodeColorMode) {
                    ForEach(DiodeColorMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Text(config.diodeColorMode.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if config.diodeShape.dividesTheRing {
                LabeledSlider(title: "Segment Gap", value: $config.diodeGap, range: 0...0.6, format: "%.2f")

                Text("Space between wedges, as a fraction of each one's width. 0 makes them meet edge to edge as one continuous ring.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LabeledSlider(title: "Diode Size", value: $config.diodeScale, range: 0.4...3.0, format: "%.2fx")

                Text("Relative to the ring's width, which crops them — above 1x the diode is taller than the band and gets trimmed by it, the way an LED reads through a slot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if config.diodeModeEnabled || config.animationType == .alternating || config.animationType == .equalizer
            || config.animationType == .sparkle || config.animationType == .multiChase {
            LabeledSlider(
                title: config.animationType == .equalizer ? "Segment Count" : config.animationType == .sparkle ? "Sparkle Count" : "Diode Count",
                value: $config.diodeCount, range: 8...60, format: "%.0f"
            )
        }

        if config.animationType == .ripple && config.diodeModeEnabled {
            GroupCaption("Drops")
            LabeledSlider(title: "Drops", value: $config.rippleDropCount, range: 1...12, format: "%.0f")
            LabeledSlider(title: "Front Width", value: $config.trailFraction, range: 0.02...0.5, format: "%.2f")
            LabeledSlider(title: "Decay", value: $config.rippleDecay, range: 0...2, format: "%.2f/s")
            LabeledSlider(title: "Drop Life", value: $config.rippleLife, range: 0.5...12, format: "%.1fs")
            LabeledSlider(title: "Loop Length", value: $config.loopSeconds, range: 1...30, format: "%.0fs")
            Stepper("Seed: \(Int(config.rippleSeed))", value: $config.rippleSeed, in: 0...999)

            Text("Drops land at seeded positions and expand both ways, overlapping and adding together. Loop Length is also the window they're placed in — each drop is evaluated a loop either side too, so one landing near the end carries into the next pass instead of cutting off.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if config.animationType == .bloom {
            LabeledSlider(title: "Patches", value: $config.bloomCount, range: 2...14, format: "%.0f")
            // `trailFraction` again, relabelled: for Bloom it's the
            // *average* patch width, which each patch then varies from by
            // its own seed. Same knob, different reading — same trick as
            // Line Width becoming Ring Width in diode mode.
            LabeledSlider(title: "Average Size", value: $config.trailFraction, range: 0.05...0.5, format: "%.2f")

            LabeledSlider(title: "Base Brightness", value: $config.bloomBase, range: 0...1, format: "%.2f")
            LabeledSlider(title: "Softness", value: $config.bloomSoftness, range: 0...1, format: "%.2f")

            Text("Each patch varies from Average Size by its own amount, so one may cover an eighth of the ring and the next a sixteenth. Base Brightness is how lit the ring stays where nothing is swelling — patches add on top of it, so there are no dark stretches. Softness diffuses their edges into a glow.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if config.animationType == .multiChase {
            // Trail length is what sets how long each color's comet is, so
            // it belongs with the chase's own controls rather than only
            // appearing for `.chasing` as it did before.
            LabeledSlider(title: "Comet Length", value: $config.trailFraction, range: 0.05...1.0, format: "%.2f")

            blinkControls

            Text("One comet per color in the Color section above — add a third or fourth color and each gets its own.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        // Outside the Multi Chase block: in diode mode the blink modulates
        // whatever animation is running, not just the chase.
        if config.diodeModeEnabled && config.animationType != .multiChase {
            blinkControls
        }

        Picker("Easing", selection: $config.easingStyle) {
            ForEach(EasingStyle.allCases) { style in
                Text(style.rawValue).tag(style)
            }
        }
        Text(config.easingStyle.summary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if config.easingStyle == .spring {
            LabeledSlider(title: "Spring Bounce", value: $config.springBounce, range: 0...1, format: "%.2f")
        }
    }


    @ViewBuilder
    private var blinkControls: some View {
        Group {
            Picker("Blink", selection: $config.blinkPattern) {
                ForEach(BlinkPattern.allCases) { pattern in
                    Text(pattern.rawValue).tag(pattern)
                }
            }
            .pickerStyle(.menu)

            Text(config.blinkPattern.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if config.blinkPattern != .steady {
                LabeledSlider(title: "Blink Rate", value: $config.blinkRate, range: 0.2...12, format: "%.1f/s")
            }
        }
    }
}

// MARK: - Shape

struct ShapeSection: View {
    @ObservedObject var config: RingConfig

    var body: some View {
        // Relabelled in diode mode: the same value, but there it reads as
        // the width of the band diodes sit in and are cropped to, which is
        // not obviously the same thing as a stroke's line width.
        LabeledSlider(
            title: config.diodeModeEnabled ? "Ring Width" : "Line Width",
            value: $config.lineWidth, range: 2...16, format: "%.0f pt"
        )
        if config.diodeModeEnabled {
            Text("The band the diodes sit in — they're cropped to it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        LabeledSlider(title: "Preview Size", value: $config.previewDiameter, range: 80...220, format: "%.0f pt")
    }
}

// MARK: - Motion Effects

struct MotionEffectsSection: View {
    @ObservedObject var config: RingConfig

    var body: some View {
        Toggle("Scale Pulse (Breathing)", isOn: $config.scalePulseEnabled)
        if config.scalePulseEnabled {
            LabeledSlider(title: "Amount", value: $config.scalePulseAmount, range: 0.02...0.4, format: "%.2f")
            LabeledSlider(title: "Speed", value: $config.scalePulseSpeed, range: 0.1...3.0, format: "%.1fx")
        }

        Toggle("Color Cycling (Hue Shift)", isOn: $config.hueShiftEnabled)
        if config.hueShiftEnabled {
            LabeledSlider(title: "Speed", value: $config.hueShiftSpeed, range: 0.02...1.0, format: "%.2fx")
            Text("Every configured color trails evenly spaced around the color wheel while active — 180° apart with just Primary/Secondary, closer together with more colors added.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Voice

struct VoiceSection: View {
    @ObservedObject var config: RingConfig
    @ObservedObject var voice: ElevenLabsVoiceService
    @ObservedObject var stt: SpeechToTextService
    @State private var pendingMessage: String = ""

    var body: some View {
        Toggle("Voice Reactive", isOn: $config.voiceReactiveEnabled)
        if config.voiceReactiveEnabled {
            LabeledSlider(title: "Sensitivity", value: $config.voiceReactiveSensitivity, range: 0.2...3.0, format: "%.1fx")
            Text("Boosts glow and scale live — from the ElevenLabs assistant below if connected, otherwise the microphone (asked for on first use).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Demo Mode (No Agent Needed)", isOn: $config.voiceDemoModeEnabled)
            if config.voiceDemoModeEnabled {
                Text("Shows the listening pill above the tab bar and live-transcribes your mic — no ElevenLabs connection required. Temporary, for demoing the pipeline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = stt.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }

        Divider()

        HStack {
            connectButton
            Spacer()
            connectionStatusLabel
        }

        if voice.connectionState == .connected {
            HStack {
                PasteableTextField("Say something…", text: $pendingMessage) { sendMessage() }
                Button("Send") { sendMessage() }
                    .disabled(pendingMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .ringGlassButtonStyle()
            }
            if !voice.lastAgentResponse.isEmpty {
                Text("“\(voice.lastAgentResponse)”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }
        }

        if let note = voice.diagnosticNote {
            Label(note, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var connectButton: some View {
        switch voice.connectionState {
        case .connected, .connecting:
            Button("Disconnect") { voice.disconnect() }
                .ringGlassButtonStyle()
        case .disconnected, .error:
            // No Agent ID/API Key fields anymore — this just connects
            // straight to the preconfigured agent in `config.elevenLabsAgentID`.
            Button("Use AI Agent") {
                voice.connect(apiKey: config.elevenLabsAPIKey, agentID: config.elevenLabsAgentID)
            }
            .ringGlassButtonStyle()
        }
    }

    @ViewBuilder
    private var connectionStatusLabel: some View {
        switch voice.connectionState {
        case .disconnected:
            Text("Not Connected")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .connecting:
            HStack(spacing: 4) {
                ProgressView()
                    #if os(macOS)
                    .controlSize(.mini)
                    #endif
                Text("Connecting…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .error(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    private func sendMessage() {
        voice.sendUserMessage(pendingMessage)
        pendingMessage = ""
    }
}

// MARK: - Glow & Blend

struct GlowBlendSection: View {
    @ObservedObject var config: RingConfig

    var body: some View {
        Toggle("Vibrancy", isOn: $config.vibrancyEnabled)
        if config.vibrancyEnabled {
            LabeledSlider(title: "Amount", value: $config.vibrancyAmount, range: 1.0...2.5, format: "%.2fx")
            Text("One knob for overall \"pop\" — boosts saturation/contrast and widens the glow together, rather than needing to retune colors and glow separately.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        Toggle("Glow", isOn: $config.glowEnabled)
        if config.glowEnabled {
            LabeledSlider(title: "Glow Radius", value: $config.glowRadius, range: 2...24, format: "%.0f pt")
        }
        LabeledSlider(title: "Blur", value: $config.blurRadius, range: 0...12, format: "%.0f pt")
        Picker("Blend Mode", selection: $config.blendMode) {
            ForEach(RingBlendMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        if config.blendMode != .normal {
            Text("Best over a dark or colorful background — try the tab bar preview.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        Toggle("Chromatic Aberration", isOn: $config.chromaticAberrationEnabled)
        if config.chromaticAberrationEnabled {
            LabeledSlider(title: "Amount", value: $config.chromaticAberrationAmount, range: 0...30, format: "%.0f pt")
            Text("Deliberately exaggerated RGB split, inspired by Siri's colorful \"wavelengths\" — not a subtle lens artifact.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Particles

struct ParticlesSection: View {
    @ObservedObject var config: RingConfig

    var body: some View {
        Toggle("Particles", isOn: $config.particlesEnabled)
        if config.particlesEnabled {
            // 20-odd raw CAEmitterLayer/CAEmitterCell knobs read as one
            // undifferentiated wall without some kind of grouping — these
            // captions split them the way Xcode's own Attributes inspector
            // splits a layer's properties: where/how particles spawn,
            // how they move once alive, then how they look.
            GroupCaption("Emission")
            Picker("Emitter Shape", selection: $config.particleEmitterShape) {
                ForEach(ParticleEmitterShape.allCases) { shape in
                    Text(shape.rawValue).tag(shape)
                }
            }
            Picker("Emitter Mode", selection: $config.particleEmitterMode) {
                ForEach(ParticleEmitterMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            LabeledSlider(title: "Emitter Size", value: $config.particleEmitterSizeMultiplier, range: 0.1...3, format: "%.1fx")
            Picker("Render Mode", selection: $config.particleRenderMode) {
                ForEach(ParticleRenderMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            LabeledSlider(title: "Birth Rate", value: $config.particleBirthRate, range: 0...40, format: "%.0f/s")
            Toggle("Pulse Birth Rate", isOn: $config.particlePulseEnabled)
            if config.particlePulseEnabled {
                LabeledSlider(title: "Pulse Period", value: $config.particlePulsePeriod, range: 0.1...3, format: "%.1fs")
            }
            LabeledSlider(title: "Emission Longitude", value: $config.particleEmissionLongitude, range: 0...360, format: "%.0f°")
            LabeledSlider(title: "Emission Spread", value: $config.particleEmissionSpread, range: 0...360, format: "%.0f°")

            GroupCaption("Motion")
            LabeledSlider(title: "Lifetime", value: $config.particleLifetime, range: 0.2...4, format: "%.1fs")
            LabeledSlider(title: "Lifetime Range", value: $config.particleLifetimeRange, range: 0...2, format: "%.1fs")
            LabeledSlider(title: "Velocity", value: $config.particleVelocity, range: 0...150, format: "%.0f pt/s")
            LabeledSlider(title: "Velocity Range", value: $config.particleVelocityRange, range: 0...80, format: "%.0f pt/s")
            LabeledSlider(title: "X Acceleration", value: $config.particleXAcceleration, range: -100...100, format: "%.0f pt/s²")
            LabeledSlider(title: "Y Acceleration", value: $config.particleYAcceleration, range: -100...100, format: "%.0f pt/s²")
            LabeledSlider(title: "Spin", value: $config.particleSpin, range: -6...6, format: "%.1f rad/s")
            LabeledSlider(title: "Spin Range", value: $config.particleSpinRange, range: 0...6, format: "%.1f rad/s")

            GroupCaption("Appearance")
            LabeledSlider(title: "Scale", value: $config.particleScale, range: 1...10, format: "%.0f pt")
            LabeledSlider(title: "Scale Range", value: $config.particleScaleRange, range: 0...5, format: "%.0f pt")
            LabeledSlider(title: "Blur", value: $config.particleBlurRadius, range: 0...20, format: "%.0f pt")
        }
    }
}

// MARK: - Playback

struct PlaybackSection: View {
    @ObservedObject var config: RingConfig

    private var loopsLabel: String {
        config.loops == 0 ? "Loops: ∞" : "Loops: \(config.loops)"
    }

    var body: some View {
        Toggle("Sequence Playback", isOn: $config.sequencePlaybackEnabled)
        if config.sequencePlaybackEnabled {
            LabeledSlider(title: "Fade In", value: $config.fadeInSeconds, range: 0...3, format: "%.1fs")
            LabeledSlider(title: "Hold", value: $config.holdSeconds, range: 0...6, format: "%.1fs")
            LabeledSlider(title: "Fade Out", value: $config.fadeOutSeconds, range: 0...3, format: "%.1fs")
            Stepper(loopsLabel, value: $config.loops, in: 0...10)
        }
    }
}

// MARK: - Background

struct BackgroundSection: View {
    @ObservedObject var config: RingConfig
    #if os(iOS)
    @State private var selectedPhotoItem: PhotosPickerItem?
    #endif

    var body: some View {
        Toggle("Background Image", isOn: $config.backgroundImageEnabled)
        if config.backgroundImageEnabled {
            backgroundImagePicker
            if config.backgroundImageData != nil {
                Button("Remove Image", role: .destructive) {
                    config.backgroundImageData = nil
                }
                .ringGlassButtonStyle()
            }
            LabeledSlider(title: "Dim", value: $config.backgroundDimAmount, range: 0...1, format: "%.2f")
        }
    }

    @ViewBuilder
    private var backgroundImagePicker: some View {
        #if os(macOS)
        Button(config.backgroundImageData == nil ? "Choose Image…" : "Change Image…") {
            pickBackgroundImageMac()
        }
        .ringGlassButtonStyle()
        #elseif os(iOS)
        PhotosPicker(config.backgroundImageData == nil ? "Choose Image…" : "Change Image…",
                     selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        config.backgroundImageData = data
                    }
                }
            }
            .ringGlassButtonStyle()
        #endif
    }

    #if os(macOS)
    private func pickBackgroundImageMac() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            config.backgroundImageData = data
        }
    }
    #endif
}

// MARK: - Liquid Glass

struct LiquidGlassSection: View {
    @ObservedObject var config: RingConfig

    var body: some View {
        Picker("Style", selection: $config.glassStyle) {
            ForEach(GlassStyle.allCases) { style in
                Text(style.rawValue).tag(style)
            }
        }
        .pickerStyle(.segmented)

        Toggle("Tint", isOn: $config.glassTintEnabled)
        if config.glassTintEnabled {
            ColorPicker("Tint Color", selection: $config.glassTintColor)
        }

        Toggle("Interactive", isOn: $config.glassInteractive)
    }
}

// MARK: - Color

struct ColorSection: View {
    @ObservedObject var config: RingConfig

    /// Continues Primary/Secondary's naming scheme instead of switching to
    /// "Color 3"/"Color 4" — matches `RingConfig.maxAdditionalColors` (4),
    /// covering up to 6 colors total. Falls back to a 1-based "Color N"
    /// only if that cap is ever raised past this list's length.
    static func ordinalName(for index: Int) -> String {
        let names = ["Tertiary", "Quaternary", "Quinary", "Senary"]
        return names.indices.contains(index) ? names[index] : "Color \(index + 3)"
    }

    var body: some View {
        ColorPicker("Primary", selection: $config.primaryColor)
        Text(config.primaryColor.hexString).font(.caption).foregroundStyle(.secondary)
        ApprovedColorSwatchGrid(selectedHex: config.primaryColor.hexString) { config.primaryColor = $0 }

        ColorPicker("Secondary", selection: $config.secondaryColor)
        Text(config.secondaryColor.hexString).font(.caption).foregroundStyle(.secondary)
        ApprovedColorSwatchGrid(selectedHex: config.secondaryColor.hexString) { config.secondaryColor = $0 }

        // Extra color slots beyond Primary/Secondary — every one of these
        // actually feeds `RingView.activeColors(elapsed:)`, so adding a
        // 3rd/4th/... color here changes what the ring renders, not just
        // what's stored. Indexed by position (not a stable id — `Color`
        // isn't `Identifiable` and duplicate colors are allowed) since the
        // list is short and never reordered, only appended to/removed
        // from.
        ForEach(Array(config.additionalColors.indices), id: \.self) { index in
            // Bounds-checked on every access: when the last row's remove
            // button fires, `additionalColors.remove(at:)` shrinks the
            // array immediately, but SwiftUI still re-evaluates this row's
            // closures once more for the exit transition using the
            // now-stale `index` — an unguarded `additionalColors[index]`
            // there is a real crash (`Index out of range`), not just a
            // theoretical one; reproduced by removing a single remaining
            // extra color slot.
            let color = config.additionalColors.indices.contains(index) ? config.additionalColors[index] : Color.white
            let name = ColorSection.ordinalName(for: index)
            HStack(spacing: 8) {
                ColorPicker(
                    name,
                    selection: Binding(
                        get: { config.additionalColors.indices.contains(index) ? config.additionalColors[index] : color },
                        set: { newValue in
                            guard config.additionalColors.indices.contains(index) else { return }
                            config.additionalColors[index] = newValue
                        }
                    )
                )
                Button {
                    guard config.additionalColors.indices.contains(index) else { return }
                    config.additionalColors.remove(at: index)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove \(name)")
            }
            Text(color.hexString).font(.caption).foregroundStyle(.secondary)
            ApprovedColorSwatchGrid(selectedHex: color.hexString) { newValue in
                guard config.additionalColors.indices.contains(index) else { return }
                config.additionalColors[index] = newValue
            }
        }

        if config.additionalColors.count < RingConfig.maxAdditionalColors {
            Button {
                // Starts on whatever App Hues swatch isn't already
                // Primary/Secondary/an existing extra color, so a freshly
                // added slot doesn't just silently duplicate one you
                // already have.
                let used = Set([config.primaryColor.hexString, config.secondaryColor.hexString] + config.additionalColors.map(\.hexString))
                let next = ApprovedColorPalette.colors.first { !used.contains($0.hex) }
                config.additionalColors.append(next?.color ?? .white)
            } label: {
                Label("Add Color", systemImage: "plus.circle")
            }
            .ringGlassButtonStyle()
        }

        if config.hueShiftEnabled {
            Text("Overridden live while color cycling is on — these are the fallback colors.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A wrapping grid of tap-to-apply swatches from `ApprovedColorPalette`
/// ("App Hues"), shown right under a `ColorPicker` so picking a brand
/// color doesn't require opening the system color picker and hunting for
/// the exact hex. All 18 swatches need to wrap across several rows at the
/// Controls panel's width — a `LazyVGrid` with adaptive columns does that
/// automatically, unlike a plain `HStack`. Whichever swatch (if any)
/// matches `selectedHex` gets a ring around it — comparing hex strings
/// rather than `Color` values directly since `Color` isn't reliably
/// `Equatable` across color spaces, and hex is already how this app treats
/// color identity everywhere else (presets, code export). Both sides of
/// the comparison come out of `Color.hexString`/`ApprovedColor.hex`'s
/// shared uppercase `"#RRGGBB"` format, so a plain `==` is enough — no
/// case-folding needed.
public struct ApprovedColorSwatchGrid: View {
    let selectedHex: String
    let onSelect: (Color) -> Void

    public init(selectedHex: String, onSelect: @escaping (Color) -> Void) {
        self.selectedHex = selectedHex
        self.onSelect = onSelect
    }

    private let columns = [GridItem(.adaptive(minimum: 20, maximum: 22), spacing: 8)]

    public var body: some View {
        GroupCaption("App Hues")
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(ApprovedColorPalette.colors) { approved in
                Button {
                    onSelect(approved.color)
                } label: {
                    Circle()
                        .fill(approved.color)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                                .padding(-2.5)
                                .opacity(selectedHex == approved.hex ? 1 : 0)
                        )
                }
                .buttonStyle(.plain)
                .help(approved.name)
            }
        }
        .padding(.bottom, 2)
    }
}

// MARK: - Shared row controls

/// A small all-caps sub-header for breaking up one long section into
/// scannable groups — used inside `ParticlesSection`, whose ~20 raw
/// CAEmitterLayer/CAEmitterCell knobs otherwise read as one undifferentiated
/// wall of sliders.
public struct GroupCaption: View {
    let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.top, 6)
    }
}

/// Applies the real `.glass` button style on macOS/iOS 26, with a plain
/// bordered fallback below that. Buttons sitting inside a `Form`/`List`/
/// toolbar already pick up Liquid Glass chrome automatically from their
/// container (see `ExportView`'s equivalent comment) — this is for buttons
/// that sit on their own instead, like the ones in `BackgroundSection`/
/// `VoiceSection` (which, since `ControlsView` moved off `Form` onto its
/// own glass cards, no longer get that for free) and `AnimationExportView`
/// in the main `RingAnimator` target (hence `public` — it needs to cross
/// the module boundary from this shared package into that executable).
public extension View {
    @ViewBuilder
    func ringGlassButtonStyle() -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

// MARK: - Shared row control

struct LabeledSlider: View {
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
                .frame(width: 52, alignment: .trailing)
        }
    }
}

/// How faithfully the ring is reproducing a real firmware pattern, and how
/// to step back from that toward something editable.
///
/// Three levels, strongest first, and they nest: an imported pattern can
/// hold all three at once, so clearing one reveals the next rather than
/// dropping to nothing.
///
/// 1. **Recorded stream** — the device's literal command stream, replayed.
///    Not a model of the output; the output.
/// 2. **Exact field** — the firmware's own `level(i, t)` maths, ported and
///    verified sample for sample. Parametric, so speed and palette still
///    mean something.
/// 3. **Interpreted** — this app's nearest equivalent animation, fully
///    editable.
///
/// Shown only when a pattern brought one of these in. A card reading
/// "Interpreted" on every hand-authored design would be noise, and this one
/// is worth noticing when it appears.
///
/// Sits directly above Animation on purpose: levels 1 and 2 override
/// `animationType`, so the override should be read before the control it
/// overrides rather than after it.
/// The other end of the fidelity dial from `FirmwareFidelitySection`.
///
/// That one asks how *true* the render is to the device; this one asks how
/// far from it you want to go. They're deliberately adjacent in the panel:
/// the accurate render and the designed one are the same animation, and
/// which you're looking at should never be a mystery.
public struct SmoothingSection: View {
    @ObservedObject var config: RingConfig

    public init(config: RingConfig) {
        self.config = config
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Gradient ring", isOn: $config.smoothingGradientRing)
                .help("Draw one continuous stroke instead of twenty separate diodes")
            LabeledSlider(
                title: "Bleed",
                value: $config.smoothingSpread,
                range: 0...3,
                format: "%.1f"
            )
            LabeledSlider(
                title: "Persistence",
                value: $config.smoothingTrail,
                range: 0...0.8,
                format: "%.2fs"
            )
            Toggle("Continuous time", isOn: $config.smoothingFluidTime)
                .help("Sample on the display's clock instead of the device's update tick")
        }
    }
}

public struct FirmwareFidelitySection: View {
    @ObservedObject var config: RingConfig

    public init(config: RingConfig) {
        self.config = config
    }

    private var stream: FirmwarePatternStream? {
        config.firmwarePatternStream.flatMap { FirmwarePatternStream.stream(named: $0) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let stream {
                level(
                    "Recorded stream",
                    detail: "\(stream.events.count) commands over \(format(stream.loopSeconds)) s, replayed at their original timestamps. This is the device's literal output — every set_color and select_led it receives. Nothing here is interpreted.",
                    symbol: "waveform.badge.checkmark",
                    tint: .green,
                    stepDown: config.firmwareLevelField != nil
                        ? "Step down to the exact maths"
                        : "Step down to an editable animation"
                ) {
                    config.firmwarePatternStream = nil
                }
            } else if let field = config.firmwareLevelField {
                level(
                    "Exact field — \(field.displayName)",
                    detail: "The firmware's own level(i, t) function, ported and verified against it sample for sample. Threshold \(format(field.threshold)), \(Int(field.tickMs)) ms tick. Colors and speed still apply; the motion is the device's.",
                    symbol: "function",
                    tint: .green,
                    stepDown: "Step down to an editable animation"
                ) {
                    config.firmwareLevelField = nil
                }
            } else {
                level(
                    "Interpreted",
                    detail: "This app's nearest equivalent to the imported pattern — close in color and cadence, not frame for frame. Every control below applies normally.",
                    symbol: "slider.horizontal.3",
                    tint: .secondary,
                    stepDown: nil,
                    action: nil
                )
            }
        }
    }

    @ViewBuilder
    private func level(
        _ title: String,
        detail: String,
        symbol: String,
        tint: Color,
        stepDown: String?,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(title, systemImage: symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
            Spacer()
        }
        Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if let stepDown, let action {
            Button(stepDown, action: action)
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }

    private func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }
}
