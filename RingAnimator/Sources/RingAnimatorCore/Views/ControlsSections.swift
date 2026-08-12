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

    var body: some View {
        Picker("Pattern style", selection: $config.patternStyle) {
            Text("Continuous (Animation Type below)").tag(LEDPatternStyle?.none)
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
            ForEach(LEDPatternStyle.allCases.filter {
                ![.continuousAnimation, .earConOnly, .notApplicable, .voiceAssistantColor, .custom].contains($0)
            }) { style in
                Text(style.displayName).tag(LEDPatternStyle?.some(style))
            }
        }
        .pickerStyle(.menu)
        Text("One of the Cue Library's canned Ziris spec-sheet behaviors (Flash, Ripple, Spin then Solid Fade, ...) instead of a continuous loop — overrides Animation Type below when set. See the Cue Library for the full set.")
            .font(.caption)
            .foregroundStyle(.secondary)

        if config.patternStyle == .flash || config.patternStyle == .quickFlash {
            Stepper("Flash count: \(config.flashCount)", value: $config.flashCount, in: 1...10)
        }

        Picker("Type", selection: $config.animationType) {
            ForEach(RingAnimationType.allCases) { type in
                Text(type.rawValue).tag(type)
            }
        }
        .pickerStyle(.menu)
        .disabled(config.patternStyle != nil)

        Text(config.animationType.summary)
            .font(.caption)
            .foregroundStyle(.secondary)

        LabeledSlider(title: "Speed", value: $config.speed, range: 0.1...3.0, format: "%.1fx")

        if config.animationType == .chasing {
            Picker("Fill style", selection: $config.chasingFillStyle) {
                ForEach(ChasingFillStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            if config.chasingFillStyle == .drawUndraw {
                Text("Grows to the peak length, then shrinks back to a point — same clockwise sweep the whole time, one pulse per lap. 1.00 draws a full circle before undrawing it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        if config.animationType == .chasing || config.animationType == .dualChase {
            LabeledSlider(
                title: config.animationType == .chasing && config.chasingFillStyle == .drawUndraw ? "Peak length" : "Trail length",
                value: $config.trailFraction, range: 0.05...1.0, format: "%.2f"
            )
        }
        if config.animationType == .alternating || config.animationType == .equalizer || config.animationType == .sparkle {
            LabeledSlider(
                title: config.animationType == .equalizer ? "Segment count" : config.animationType == .sparkle ? "Sparkle count" : "Diode count",
                value: $config.diodeCount, range: 8...60, format: "%.0f"
            )
        }

        Picker("Easing", selection: $config.easingStyle) {
            ForEach(EasingStyle.allCases) { style in
                Text(style.rawValue).tag(style)
            }
        }
        Text(config.easingStyle.summary)
            .font(.caption)
            .foregroundStyle(.secondary)
        if config.easingStyle == .spring {
            LabeledSlider(title: "Spring bounce", value: $config.springBounce, range: 0...1, format: "%.2f")
        }
    }
}

// MARK: - Shape

struct ShapeSection: View {
    @ObservedObject var config: RingConfig

    var body: some View {
        LabeledSlider(title: "Line width", value: $config.lineWidth, range: 2...16, format: "%.0f pt")
        LabeledSlider(title: "Preview size", value: $config.previewDiameter, range: 80...220, format: "%.0f pt")
    }
}

// MARK: - Motion Effects

struct MotionEffectsSection: View {
    @ObservedObject var config: RingConfig

    var body: some View {
        Toggle("Scale pulse (breathing)", isOn: $config.scalePulseEnabled)
        if config.scalePulseEnabled {
            LabeledSlider(title: "Amount", value: $config.scalePulseAmount, range: 0.02...0.4, format: "%.2f")
            LabeledSlider(title: "Speed", value: $config.scalePulseSpeed, range: 0.1...3.0, format: "%.1fx")
        }

        Toggle("Color cycling (hue shift)", isOn: $config.hueShiftEnabled)
        if config.hueShiftEnabled {
            LabeledSlider(title: "Speed", value: $config.hueShiftSpeed, range: 0.02...1.0, format: "%.2fx")
            Text("Secondary color trails 180° behind primary while active.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        Toggle("Voice reactive", isOn: $config.voiceReactiveEnabled)
        if config.voiceReactiveEnabled {
            LabeledSlider(title: "Sensitivity", value: $config.voiceReactiveSensitivity, range: 0.2...3.0, format: "%.1fx")
            Text("Boosts glow and scale live — from the ElevenLabs assistant below if connected, otherwise the microphone (asked for on first use).")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Demo mode (no agent needed)", isOn: $config.voiceDemoModeEnabled)
            if config.voiceDemoModeEnabled {
                Text("Shows the listening pill above the tab bar and live-transcribes your mic — no ElevenLabs connection required. Temporary, for demoing the pipeline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            Text("Not connected")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .connecting:
            HStack(spacing: 4) {
                ProgressView()
                    #if os(macOS)
                    .controlSize(.mini)
                    #endif
                Text("Connecting…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        }

        Toggle("Glow", isOn: $config.glowEnabled)
        if config.glowEnabled {
            LabeledSlider(title: "Glow radius", value: $config.glowRadius, range: 2...24, format: "%.0f pt")
        }
        LabeledSlider(title: "Blur", value: $config.blurRadius, range: 0...12, format: "%.0f pt")
        Picker("Blend mode", selection: $config.blendMode) {
            ForEach(RingBlendMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        if config.blendMode != .normal {
            Text("Best over a dark or colorful background — try the tab bar preview.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Toggle("Chromatic aberration", isOn: $config.chromaticAberrationEnabled)
        if config.chromaticAberrationEnabled {
            LabeledSlider(title: "Amount", value: $config.chromaticAberrationAmount, range: 0...30, format: "%.0f pt")
            Text("Deliberately exaggerated RGB split, inspired by Siri's colorful \"wavelengths\" — not a subtle lens artifact.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            Picker("Emitter shape", selection: $config.particleEmitterShape) {
                ForEach(ParticleEmitterShape.allCases) { shape in
                    Text(shape.rawValue).tag(shape)
                }
            }
            Picker("Emitter mode", selection: $config.particleEmitterMode) {
                ForEach(ParticleEmitterMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            LabeledSlider(title: "Emitter size", value: $config.particleEmitterSizeMultiplier, range: 0.1...3, format: "%.1fx")
            Picker("Render mode", selection: $config.particleRenderMode) {
                ForEach(ParticleRenderMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            LabeledSlider(title: "Birth rate", value: $config.particleBirthRate, range: 0...40, format: "%.0f/s")
            Toggle("Pulse birth rate", isOn: $config.particlePulseEnabled)
            if config.particlePulseEnabled {
                LabeledSlider(title: "Pulse period", value: $config.particlePulsePeriod, range: 0.1...3, format: "%.1fs")
            }
            LabeledSlider(title: "Emission longitude", value: $config.particleEmissionLongitude, range: 0...360, format: "%.0f°")
            LabeledSlider(title: "Emission spread", value: $config.particleEmissionSpread, range: 0...360, format: "%.0f°")

            GroupCaption("Motion")
            LabeledSlider(title: "Lifetime", value: $config.particleLifetime, range: 0.2...4, format: "%.1fs")
            LabeledSlider(title: "Lifetime range", value: $config.particleLifetimeRange, range: 0...2, format: "%.1fs")
            LabeledSlider(title: "Velocity", value: $config.particleVelocity, range: 0...150, format: "%.0f pt/s")
            LabeledSlider(title: "Velocity range", value: $config.particleVelocityRange, range: 0...80, format: "%.0f pt/s")
            LabeledSlider(title: "X acceleration", value: $config.particleXAcceleration, range: -100...100, format: "%.0f pt/s²")
            LabeledSlider(title: "Y acceleration", value: $config.particleYAcceleration, range: -100...100, format: "%.0f pt/s²")
            LabeledSlider(title: "Spin", value: $config.particleSpin, range: -6...6, format: "%.1f rad/s")
            LabeledSlider(title: "Spin range", value: $config.particleSpinRange, range: 0...6, format: "%.1f rad/s")

            GroupCaption("Appearance")
            LabeledSlider(title: "Scale", value: $config.particleScale, range: 1...10, format: "%.0f pt")
            LabeledSlider(title: "Scale range", value: $config.particleScaleRange, range: 0...5, format: "%.0f pt")
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
        Toggle("Sequence playback", isOn: $config.sequencePlaybackEnabled)
        if config.sequencePlaybackEnabled {
            LabeledSlider(title: "Hold", value: $config.holdSeconds, range: 0...6, format: "%.1fs")
            LabeledSlider(title: "Fade out", value: $config.fadeOutSeconds, range: 0...3, format: "%.1fs")
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
        Toggle("Background image", isOn: $config.backgroundImageEnabled)
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
            ColorPicker("Tint color", selection: $config.glassTintColor)
        }

        Toggle("Interactive", isOn: $config.glassInteractive)
    }
}

// MARK: - Color

struct ColorSection: View {
    @ObservedObject var config: RingConfig

    var body: some View {
        ColorPicker("Primary", selection: $config.primaryColor)
        Text(config.primaryColor.hexString).font(.caption).foregroundStyle(.secondary)
        ColorPicker("Secondary", selection: $config.secondaryColor)
        Text(config.secondaryColor.hexString).font(.caption).foregroundStyle(.secondary)
        if config.hueShiftEnabled {
            Text("Overridden live while color cycling is on — these are the fallback colors.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Shared row controls

/// A small all-caps sub-header for breaking up one long section into
/// scannable groups — used inside `ParticlesSection`, whose ~20 raw
/// CAEmitterLayer/CAEmitterCell knobs otherwise read as one undifferentiated
/// wall of sliders.
struct GroupCaption: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
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
