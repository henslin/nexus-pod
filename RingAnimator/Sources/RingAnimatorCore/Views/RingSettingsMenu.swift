import SwiftUI

/// iOS's Settings-app-style entry point to every ring control — a `List`
/// of `NavigationLink`s, one per section from `ControlsSections.swift`,
/// each pushing to its own `Form` instead of Mac's single long scroll.
/// Same underlying section content as `ControlsView` (Mac), just a
/// different container shape — nothing about a knob's range, default, or
/// behavior can drift between platforms because both read the exact same
/// `AnimationSection`/`ShapeSection`/etc. structs.
///
/// Also owns the one thing that isn't part of `RingConfig` at all: the
/// "Preview" row, which is how you're *looking* at the ring right now
/// (light/dark, bundled App UI on/off) rather than a property of the ring
/// itself — passed in as bindings from `RootView` so that state keeps
/// living there, not here.
public struct RingSettingsMenu: View {
    @ObservedObject var config: RingConfig
    @ObservedObject private var voice: ElevenLabsVoiceService
    @ObservedObject private var stt: SpeechToTextService
    @Binding var isDarkMode: Bool
    @Binding var showAppUI: Bool

    public init(config: RingConfig, isDarkMode: Binding<Bool>, showAppUI: Binding<Bool>) {
        self.config = config
        self.voice = config.elevenLabs
        self.stt = config.voiceConversation.stt
        self._isDarkMode = isDarkMode
        self._showAppUI = showAppUI
    }

    public var body: some View {
        List {
            Section {
                NavigationLink {
                    Form {
                        Section {
                            Picker("Appearance", selection: $isDarkMode) {
                                Text("Light").tag(false)
                                Text("Dark").tag(true)
                            }
                            .pickerStyle(.segmented)
                            Toggle("App UI", isOn: $showAppUI)
                        } footer: {
                            Text("How you're viewing the ring right now — not saved as part of the design.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .formStyle(.grouped)
                    .navigationTitle("Preview")
                    .inlineNavigationTitleIfAvailable()
                } label: {
                    Label("Preview", systemImage: "eye")
                }
            }

            // Same order Mac's `ControlsView` cards use — "the ring's own
            // look" first (Color, Animation, Shape, Motion Effects, Glow &
            // Blend, Particles), then "how it's staged for this demo"
            // (Playback, Voice, Background, Liquid Glass) — plus matching
            // icons, so the two platforms read as the same settings
            // reorganized into two different container shapes rather than
            // two independently-ordered menus.
            Section {
                NavigationLink {
                    Form { Section { ColorSection(config: config) } }
                        .formStyle(.grouped)
                        .navigationTitle("Color")
                        .inlineNavigationTitleIfAvailable()
                } label: {
                    Label("Color", systemImage: "paintpalette")
                }
                NavigationLink {
                    Form { Section { AnimationSection(config: config) } }
                        .formStyle(.grouped)
                        .navigationTitle("Animation")
                        .inlineNavigationTitleIfAvailable()
                } label: {
                    Label("Animation", systemImage: "play.circle")
                }
                NavigationLink {
                    Form { Section { ShapeSection(config: config) } }
                        .formStyle(.grouped)
                        .navigationTitle("Shape")
                        .inlineNavigationTitleIfAvailable()
                } label: {
                    Label("Shape", systemImage: "circle.dashed")
                }
                NavigationLink {
                    Form {
                        Section {
                            MotionEffectsSection(config: config)
                        } footer: {
                            Text("Layer these on top of any animation type above.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .formStyle(.grouped)
                    .navigationTitle("Motion Effects")
                    .inlineNavigationTitleIfAvailable()
                } label: {
                    Label("Motion Effects", systemImage: "arrow.triangle.2.circlepath")
                }
                NavigationLink {
                    Form { Section { GlowBlendSection(config: config) } }
                        .formStyle(.grouped)
                        .navigationTitle("Glow & Blend")
                        .inlineNavigationTitleIfAvailable()
                } label: {
                    Label("Glow & Blend", systemImage: "sun.max")
                }
                NavigationLink {
                    Form {
                        Section {
                            ParticlesSection(config: config)
                        } footer: {
                            Text("Raw CAEmitterLayer/CAEmitterCell controls — the same particle system UIKit/AppKit apps use.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .formStyle(.grouped)
                    .navigationTitle("Particles")
                    .inlineNavigationTitleIfAvailable()
                } label: {
                    Label("Particles", systemImage: "sparkles")
                }
                NavigationLink {
                    Form {
                        Section {
                            PlaybackSection(config: config)
                        } footer: {
                            Text("Off = loops forever, like a live status indicator. On = plays the same hold/fade envelope the Cue Library uses, so you can preview it as a one-shot cue.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .formStyle(.grouped)
                    .navigationTitle("Playback")
                    .inlineNavigationTitleIfAvailable()
                } label: {
                    Label("Playback", systemImage: "repeat")
                }
                NavigationLink {
                    Form {
                        Section {
                            VoiceSection(config: config, voice: voice, stt: stt)
                        } footer: {
                            Text("Connects to a preconfigured ElevenLabs Conversational AI agent so the ring reacts to actual assistant speech instead of a simulated level.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .formStyle(.grouped)
                    .navigationTitle("Voice")
                    .inlineNavigationTitleIfAvailable()
                } label: {
                    Label("Voice", systemImage: "waveform")
                }
                NavigationLink {
                    Form {
                        Section {
                            BackgroundSection(config: config)
                        } footer: {
                            Text("Shows behind the tab bar — a manual way to test any reference PNG, on top of (and taking priority over) the bundled \"App UI\" screenshots.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .formStyle(.grouped)
                    .navigationTitle("Background")
                    .inlineNavigationTitleIfAvailable()
                } label: {
                    Label("Background", systemImage: "photo")
                }
                NavigationLink {
                    Form {
                        Section {
                            LiquidGlassSection(config: config)
                        } footer: {
                            Text("The real Glass API's own parameters — style, tint, and interactive — applied to the tab bar and ring pod below.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .formStyle(.grouped)
                    .navigationTitle("Liquid Glass")
                    .inlineNavigationTitleIfAvailable()
                } label: {
                    Label("Liquid Glass", systemImage: "wand.and.stars")
                }
            }
        }
        .navigationTitle("Ring Settings")
        .inlineNavigationTitleIfAvailable()
    }
}

private extension View {
    /// `.navigationBarTitleDisplayMode` is a UIKit-backed, iOS/tvOS-only
    /// API — macOS's SwiftUI has no equivalent concept (no navigation bar
    /// with a compact/inline/large title mode), so calling it directly
    /// fails to compile there. `RingSettingsMenu` only ever runs on iOS,
    /// but it lives in the shared cross-platform `RingAnimatorCore`
    /// package (same reasoning as `TabBarPreview`/`VoicePillView` living
    /// here), so the Mac build compiles this file too — this makes every
    /// call site above a harmless no-op on macOS instead of a build
    /// error, without needing a `#if os(iOS)` wrapped around all twelve
    /// of them individually.
    @ViewBuilder
    func inlineNavigationTitleIfAvailable() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
