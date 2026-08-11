import SwiftUI

/// Mac app's Controls panel — one long scrolling `Form`, every section
/// stacked in order. The section *content* itself lives in
/// `ControlsSections.swift`, shared with the iOS app's drill-down menu
/// (`RingSettingsMenu`) so the two never drift apart — this file just
/// arranges those shared pieces into Mac's single-scroll layout with the
/// same headers/footers it's always had.
public struct ControlsView: View {
    @ObservedObject var config: RingConfig
    /// Observed directly (rather than read through `config.elevenLabs`
    /// each time) so this view redraws when connection state, level, or
    /// transcripts change — see `RingConfig.elevenLabs`'s doc comment for
    /// why `RingView` doesn't need the same thing.
    @ObservedObject private var voice: ElevenLabsVoiceService
    /// Observed directly (same reasoning as `voice` above) so a listening
    /// failure — permission denied, no recognizer, engine wouldn't start —
    /// shows up immediately instead of silently doing nothing.
    @ObservedObject private var stt: SpeechToTextService

    public init(config: RingConfig) {
        self.config = config
        self.voice = config.elevenLabs
        self.stt = config.voiceConversation.stt
    }

    public var body: some View {
        Form {
            Section("Animation") {
                AnimationSection(config: config)
            }

            Section("Shape") {
                ShapeSection(config: config)
            }

            Section {
                MotionEffectsSection(config: config)
            } header: {
                Text("Motion Effects")
            } footer: {
                Text("Layer these on top of any animation type above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                VoiceSection(config: config, voice: voice, stt: stt)
            } header: {
                Text("Voice")
            } footer: {
                Text("Connects to a preconfigured ElevenLabs Conversational AI agent so the ring reacts to actual assistant speech instead of a simulated level.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Glow & Blend") {
                GlowBlendSection(config: config)
            }

            Section {
                ParticlesSection(config: config)
            } header: {
                Text("Particles")
            } footer: {
                Text("Raw CAEmitterLayer/CAEmitterCell controls — the same particle system UIKit/AppKit apps use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                PlaybackSection(config: config)
            } header: {
                Text("Playback")
            } footer: {
                Text("Off = loops forever, like a live status indicator. On = plays the same hold/fade envelope the Cue Library uses, so you can preview it as a one-shot cue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                BackgroundSection(config: config)
            } header: {
                Text("Background")
            } footer: {
                Text("Shows behind the tab bar in the iPhone preview below — a manual way to test any reference PNG, on top of (and taking priority over) the bundled \"App UI\" screenshots. Doesn't affect the large preview.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LiquidGlassSection(config: config)
            } header: {
                Text("Liquid Glass")
            } footer: {
                Text("The real Glass API's own parameters — style, tint, and interactive — applied to the floating tab bar and ring pod in the iPhone preview below, and the ring button on iOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Color") {
                ColorSection(config: config)
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
        .frame(minWidth: 320)
        #endif
    }
}
