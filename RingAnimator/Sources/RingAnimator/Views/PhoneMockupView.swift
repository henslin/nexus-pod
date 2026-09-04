import SwiftUI
import AppKit
import RingAnimatorCore

/// A hand-drawn device frame, roughly iPhone 17 Pro proportioned — for
/// previewing `TabBarPreview` the way it'll actually sit on a real phone: a
/// Dynamic Island and the floating Liquid Glass tab bar + ring pod
/// anchored to the bottom. Behind the bar (see `screen`), in priority
/// order: a manually-picked custom image (`RingConfig.backgroundImageEnabled`,
/// set from the Controls panel's "Background image" section — for testing
/// arbitrary reference PNGs beyond the bundled set), then the bundled "App
/// UI" screenshot for the selected tab, then a flat page background if
/// neither is on. Tap a tab to switch its selection state (the "App UI"
/// screenshot behind the bar switches too). A Light/Dark toggle lets the
/// whole mockup — phone body, screen content, tab bar, ring pod — preview
/// both appearances. `isDarkMode` is owned one level up, by `PreviewTab` in
/// `ContentView.swift`, and passed down as a `@Binding` — `PreviewTab`
/// applies the same override to the large preview's glass, so this one
/// toggle drives both previews together instead of only the phone.
///
/// An earlier version of this file also hand-rolled a drag-to-swipe
/// gesture on the content to simulate iOS's swipe-between-tabs. That's
/// been removed: no amount of hand-rolled AppKit trackpad gesture code can
/// genuinely reproduce iOS's touchscreen swipe + interactive Liquid Glass
/// tab-bar morph — that's real system behavior, private to UIKit/SwiftUI
/// running on an actual iOS host. `RootView` already gets the real thing
/// for free, by being a completely untouched, standard `TabView` — that's
/// the place to experience genuine "out of the box" iOS 27 tab bar
/// behavior (Simulator or a real device), not this Mac-hosted mockup.
/// This mockup stays tap-only.
///
/// Trackpad pinch-to-zoom lives on `deviceFrame` via `ZoomableCanvas`
/// (same folder) — a real `NSScrollView` with `allowsMagnification`,
/// double-click to reset to actual size, and a live "150%"-style badge
/// that tracks your fingers in real time. This was blocked for a long
/// time by an unrelated bug (the app never actually becoming the active
/// app when launched from Xcode — see `RingAnimatorApp.swift`), not
/// anything about the zoom mechanism itself, which is why it's back as
/// the genuine Apple-supported approach rather than a hand-rolled gesture.
///
/// The canvas fills the entire Preview pane (Figma/Sketch style — one big
/// zoomable/pannable surface, not a box hugging the phone) rather than
/// being sized exactly to the phone's own pixel dimensions the way it was
/// originally. `ZoomableCanvas.contentSize` still describes the phone's
/// actual size (what "100%"/double-click-to-reset means); the view itself
/// just gets `.frame(maxWidth: .infinity, maxHeight: .infinity)` so
/// AppKit hands its `NSScrollView` however much space `PreviewTab` (in
/// `ContentView.swift`) actually has, and `CenteringClipView` (see
/// `ZoomableCanvas.swift`) keeps the phone centered in whatever that
/// turns out to be. The appearance/App-UI controls and the zoom hint
/// float as overlays instead of stacking above the canvas, so they don't
/// eat into that space.
///

/// The ring pod itself has a duplicate ring behind it (see
/// `TabBarPreview.ringPodStack`) — same size, exactly centered, sitting
/// behind the Liquid Glass material so it's genuinely refracted rather
/// than just sitting on top.
struct PhoneMockupView: View {
    @ObservedObject var config: RingConfig
    /// Observed directly (same reasoning as `ControlsView.voice`) so this
    /// view redraws when the hands-free loop starts/stops — `config`
    /// alone doesn't republish changes to nested observable objects it
    /// owns, only its own `@Published` properties.
    @ObservedObject private var voiceConversation: VoiceConversationController
    @State private var selectedTab: DemoTab = .dashboard
    /// Drives the pill's actual presence in the view tree — deliberately
    /// decoupled from `voiceConversation.isVisible` so disappearing can play
    /// a quick upward lift *before* the shrink-back-to-the-ring transition
    /// starts, instead of both happening at once. See the `onChange` below.
    @State private var pillPresented = false
    /// Extra manual offset for that pre-exit lift — separate from the
    /// shrink/offset math in `GrowFromRingModifier` so the two motions
    /// stack cleanly (lift up, then reset to 0 right as the shrink begins).
    @State private var pillLiftOffset: CGFloat = 0
    /// Drives the Export Animation sheet — see `AnimationExportView`, wired
    /// in via `controlsBar` below.
    @State private var isExportingAnimation = false

    /// Non-nil while a timeline is driving the pod — passed straight down
    /// to `TabBarPreview`, see its own `playback` property.
    var playback: TimelinePlayback?
    /// The sequence, if there is one — only used to offer it as an export
    /// source in the Export Animation sheet. Empty by default, which is
    /// what makes that option simply not appear.
    var timeline: RingTimeline = RingTimeline()

    /// Carried so the zoomable canvas can put the viewport back where it
    /// was after being rebuilt — see `StageState`.
    var stageState: StageState?

    init(
        config: RingConfig,
        isDarkMode: Binding<Bool>,
        deviceFinish: Binding<AnimationExporter.DeviceFinish>,
        playback: TimelinePlayback? = nil,
        timeline: RingTimeline = RingTimeline(),
        stageState: StageState? = nil
    ) {
        self.config = config
        self.timeline = timeline
        self.voiceConversation = config.voiceConversation
        self._isDarkMode = isDarkMode
        self._deviceFinish = deviceFinish
        self.playback = playback
        self.stageState = stageState
    }

    /// Shared with `PreviewTab`'s large preview — see the type doc comment.
    @Binding var isDarkMode: Bool
    /// Which iPhone the mockup wears. A binding for the same reason
    /// `isDarkMode` is one: it lives in `StageState`, so the choice
    /// survives switching sections.
    @Binding var deviceFinish: AnimationExporter.DeviceFinish
    /// When on, real app-UI screenshots (`Resources/DemoScreens.xcassets`)
    /// render behind the tab bar instead of a flat page background —
    /// matched to the selected tab and to `isDarkMode`.
    @State private var showAppUI = false

    // Roughly iPhone 17 Pro proportioned.
    // Shared with the exporter, so an exported App UI frame and this
    // mockup can't drift apart.
    private let screenWidth = AnimationExporter.phoneScreenSize.width
    private let screenHeight = AnimationExporter.phoneScreenSize.height
    /// The frame artwork is opaque outside its aperture, so it masks the
    /// screen's own corners — nothing here needs a corner radius any more.
    private let frameWidth = AnimationExporter.phoneFrameSize.width
    private let frameHeight = AnimationExporter.phoneFrameSize.height

    var body: some View {
        ZoomableCanvas(
            contentSize: AnimationExporter.phoneFrameSize,
            minMagnification: 0.25,
            maxMagnification: 4,
            restMagnification: 1,
            viewport: stageState
        ) {
            deviceFrame
                // Applied here, above deviceFrame, so the phone body, the
                // screen content, the Liquid Glass tab bar, and the ring
                // pod all pick up the chosen appearance together.
                .environment(\.colorScheme, isDarkMode ? .dark : .light)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
        .overlay(alignment: .top) {
            controlsBar
                .padding(.top, 16)
        }
        .overlay(alignment: .bottomLeading) {
            Text("Pinch to zoom · double-click to reset")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassBackground(in: Capsule())
                .padding(14)
        }
        .sheet(isPresented: $isExportingAnimation) {
            AnimationExportView(
                config: config,
                timeline: timeline,
                colorScheme: isDarkMode ? .dark : .light,
                deviceFinish: deviceFinish,
                onDismiss: { isExportingAnimation = false }
            )
        }
    }

    private var controlsBar: some View {
        HStack(spacing: 28) {
            appearancePicker
            finishPicker
            Toggle("App UI", isOn: $showAppUI)
                .toggleStyle(.switch)
                .fixedSize()
            Button {
                isExportingAnimation = true
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help("Export Animation…")
            .ringGlassButtonStyle()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassBackground(in: Capsule())
    }

    private var appearancePicker: some View {
        Picker("Appearance", selection: $isDarkMode) {
            Text("Light").tag(false)
            Text("Dark").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(width: 180)
    }

    /// Apple's own iPhone 17 Pro artwork, with the screen behind it.
    ///
    /// This used to be a drawn rounded rectangle with a capsule for the
    /// Dynamic Island. The real frame needs no such approximating: its
    /// aperture is exactly `phoneScreenSize` at 3x and exactly centred
    /// (measured, not assumed — see `AnimationExporter.phoneFrameSize`),
    /// so the screen just sits behind it and the artwork masks the
    /// corners and supplies the island.
    /// Which iPhone the mockup wears. Menu rather than a segmented control
    /// — three finish names don't fit the bar legibly, and this is a
    /// choice made once rather than toggled back and forth the way
    /// light/dark is.
    private var finishPicker: some View {
        Picker("Finish", selection: $deviceFinish) {
            ForEach(AnimationExporter.DeviceFinish.allCases) { finish in
                Text(finish.rawValue).tag(finish)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(width: 150)
    }

    private var deviceFrame: some View {
        ZStack {
            screen
                .frame(width: screenWidth, height: screenHeight)
                // Same clip the export uses — see
                // `AnimationExporter.phoneScreenCornerRadius`.
                .clipShape(RoundedRectangle(cornerRadius: AnimationExporter.phoneScreenCornerRadius, style: .continuous))

            deviceFinish.image
                .resizable()
                .frame(width: frameWidth, height: frameHeight)
                // The frame is a picture of a phone, not a control — taps
                // belong to the tab bar and pod behind it.
                .allowsHitTesting(false)
        }
        .frame(width: frameWidth, height: frameHeight)
    }

    /// Custom background image (manually picked, from the Controls panel)
    /// takes priority over "App UI" if both happen to be on — it's the
    /// "test some other PNG" escape hatch, so it should win when set.
    /// Falls through to the bundled per-tab screenshot, then to a flat
    /// page background if neither source is active.
    private var screen: some View {
        ZStack(alignment: .bottom) {
            if config.backgroundImageEnabled, let image = customBackgroundImage {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: screenWidth, height: screenHeight)
                    .clipped()
                    .overlay(Color.black.opacity(config.backgroundDimAmount))
            } else if showAppUI {
                selectedTab.screenshotImage(dark: isDarkMode)
                    .resizable()
                    .scaledToFill()
                    .frame(width: screenWidth, height: screenHeight)
                    .clipped()
            } else {
                DemoColors.pageBackground
            }

            VStack(spacing: 10) {
                if pillPresented {
                    // Same width as the tab bar + ring pod row below, so the
                    // pill reads as part of the same bottom cluster instead
                    // of a narrower, separate element.
                    VoicePillView(controller: voiceConversation, width: screenWidth - 42, primaryColor: config.primaryColor, secondaryColor: config.secondaryColor)
                        .offset(y: pillLiftOffset)
                        .transition(.growFromRing(rowWidth: screenWidth - 42))
                }
                TabBarPreview(config: config, selectedTab: $selectedTab, width: screenWidth - 42, playback: playback)
            }
            .padding(.bottom, 21)
            .onAppear {
                // Sync without animating in case the loop is already active
                // when this view first appears.
                pillPresented = voiceConversation.isVisible
            }
            .onChange(of: voiceConversation.isVisible) { _, isVisible in
                // `.bouncy` is the real iOS spring preset — a touch of
                // overshoot instead of the more clinical critically-damped
                // spring used before. Drives the scale/offset/opacity
                // transform in `.growFromRing` below.
                if isVisible {
                    pillLiftOffset = 0
                    withAnimation(.bouncy(duration: 0.45, extraBounce: 0.08)) {
                        pillPresented = true
                    }
                } else {
                    // Two-stage exit: a quick upward nudge plays first, then
                    // (once that settles) the actual shrink-back-into-the-ring
                    // removal transition — rather than shrinking straight
                    // back down in one motion.
                    withAnimation(.easeOut(duration: 0.12)) {
                        pillLiftOffset = -8
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        pillLiftOffset = 0
                        withAnimation(.bouncy(duration: 0.45, extraBounce: 0.08)) {
                            pillPresented = false
                        }
                    }
                }
            }
        }
    }

    private var customBackgroundImage: Image? {
        guard let data = config.backgroundImageData, let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
    }
}
