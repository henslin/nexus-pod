import SwiftUI
#if os(iOS)
import UIKit
#endif
import RingAnimatorCore

/// Root screen — the same floating tab bar + detached ring pod
/// (`TabBarPreview`) the Mac app's phone mockup uses, anchored to the
/// bottom over a blank canvas you can swap for a bundled reference
/// "App UI" screenshot or your own photo. One component, not two
/// hand-kept-in-sync copies — see `TabBarPreview`'s doc comment.
///
/// Tried a couple of "more native" alternatives first — a native
/// `TabView` with the ring as a `role: .search` prominent tab, and a
/// native `TabView` with the pod composited beside it — neither actually
/// looked right once running. `TabBarPreview` is the one that's proven:
/// it's what the Mac mockup has used all along, it puts the ring pod
/// exactly beside the tabs (not on or above them), and it's real Liquid
/// Glass. The one real tradeoff is tap-only tab switching, not swipe.
///
/// Tapping the ring pod opens every tunable parameter
/// (`RingSettingsMenu`) in a sheet. While it's open, the bar + ring lift
/// to sit above the sheet instead of being covered by it, so the ring
/// stays visible while you're adjusting what's making it look that way.
///
/// Also mirrors `PhoneMockupView`'s "listening/speaking" voice pill
/// (`VoicePillView`) above the tab bar whenever a hands-free ElevenLabs
/// conversation is active — same shared component, same grow-from-the-
/// ring entrance/exit, wired to `config.voiceConversation` exactly the
/// way the Mac mockup is.
struct RootView: View {
    @StateObject private var config: RingConfig
    /// Observed directly (same reasoning as `ControlsView`'s `voice`/`stt`
    /// properties) so this view redraws when the conversation's
    /// visibility, mode, level, or messages change — `RingConfig` itself
    /// doesn't republish a held reference type's own changes.
    @ObservedObject private var voiceConversation: VoiceConversationController

    @State private var showingSettings = false
    @State private var selectedTab: DemoTab = .dashboard

    /// Preview-only state — how you're *looking* at the ring right now,
    /// not part of the ring's own configuration, so it stays local here
    /// rather than living on `RingConfig`. Lives in `RingSettingsMenu`'s
    /// "Preview" row, via the bindings passed into the sheet below.
    @State private var isDarkMode = true
    @State private var showAppUI = false

    /// Drives `VoicePillView`'s presence/entrance-exit — see
    /// `PhoneMockupView`'s identical pair for the full reasoning (kept in
    /// sync with `voiceConversation.isVisible` in `.onAppear`/`.onChange`
    /// below rather than driven directly, so the two-stage exit animation
    /// there can run before the view actually disappears).
    @State private var pillPresented = false
    @State private var pillLiftOffset: CGFloat = 0

    /// The settings sheet's own fixed height, in points — deliberately a
    /// concrete number we chose (via `.presentationDetents([.height(...)])`
    /// below) rather than `.medium`, so the tab bar's lift-above-the-sheet
    /// offset can match it exactly instead of estimating a percentage of
    /// screen height that never quite lined up (see the `body` comment
    /// at the padding call site).
    private static let sheetDetentHeight: CGFloat = 500
    /// Extra clearance above the sheet's top edge — covers its rounded
    /// corners/drag grabber so the tab bar visibly sits clear of it
    /// rather than butting right up against the edge.
    private static let tabBarLiftMargin: CGFloat = 28
    /// Resting bottom padding when the sheet is closed. Bumped up from
    /// the Mac mockup's 8pt — on-device that read as sitting too close to
    /// the bottom edge/home indicator, which is what "always ends up too
    /// low" was describing.
    private static let tabBarRestPadding: CGFloat = 24

    init() {
        let config = RingConfig()
        _config = StateObject(wrappedValue: config)
        _voiceConversation = ObservedObject(wrappedValue: config.voiceConversation)
    }

    var body: some View {
        GeometryReader { geo in
            let rowWidth = geo.size.width - 32

            ZStack(alignment: .bottom) {
                background(size: geo.size)

                VStack(spacing: 10) {
                    if pillPresented {
                        // Same width as the tab bar + ring pod row below,
                        // so the pill reads as part of the same bottom
                        // cluster instead of a narrower, separate element.
                        VoicePillView(controller: voiceConversation, width: rowWidth, primaryColor: config.primaryColor, secondaryColor: config.secondaryColor)
                            .offset(y: pillLiftOffset)
                            .transition(.growFromRing(rowWidth: rowWidth))
                    }

                    TabBarPreview(
                        config: config,
                        selectedTab: $selectedTab,
                        width: rowWidth,
                        onRingTap: { showingSettings = true }
                    )
                }
                // Fixed constants, not a fraction of `geo.size.height` —
                // the old version tried to guess the sheet's height as a
                // percentage of screen height, but `geo` here reports the
                // *safe-area-constrained* size while `.presentationDetents`
                // measures from the true screen edge, so the two were
                // never quite measuring the same thing (that's what caused
                // both the "still overlapping" and "settles too low"
                // reports). `sheetDetentHeight` below is a height *we*
                // chose for the sheet, so lining this up against it is
                // exact math, not an estimate.
                .padding(.bottom, showingSettings ? Self.sheetDetentHeight + Self.tabBarLiftMargin : Self.tabBarRestPadding)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showingSettings)
                .onAppear {
                    // Sync without animating in case the loop is already
                    // active when this view first appears.
                    pillPresented = voiceConversation.isVisible
                }
                .onChange(of: voiceConversation.isVisible) { _, isVisible in
                    if isVisible {
                        pillLiftOffset = 0
                        withAnimation(.bouncy(duration: 0.45, extraBounce: 0.08)) {
                            pillPresented = true
                        }
                    } else {
                        // Two-stage exit: a quick upward nudge plays first,
                        // then (once that settles) the actual
                        // shrink-back-into-the-ring removal transition —
                        // rather than shrinking straight back down in one
                        // motion.
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
            .frame(width: geo.size.width, height: geo.size.height)
        }
        // `.preferredColorScheme`, not plain `.environment(\.colorScheme,
        // ...)` — the sheet's `Form`/grouped list chrome and the
        // presentation's own material are UIKit-backed and follow the
        // view controller's actual interface style, which only
        // `.preferredColorScheme` sets (it forces
        // `overrideUserInterfaceStyle`, not just the SwiftUI environment
        // value). That's why the ring itself was following the toggle
        // but the sheet stayed light regardless. Applied above `.sheet`
        // so the presented sheet inherits it too.
        .preferredColorScheme(isDarkMode ? .dark : .light)
        #if os(iOS)
        // The bundled "App UI" screenshots already have their own status
        // bar baked into the image (that's what makes them read as a
        // real app, not a blank rectangle) — with the simulator's own
        // live status bar drawn on top of it too, the two rarely land in
        // exactly the same place (they were captured on a different
        // device size than whatever you're running), which is the
        // garbled double-clock/black-pill glitch. Hiding the real one
        // only while a screenshot's showing leaves just the baked-in one
        // visible, which is the one that's actually supposed to be seen.
        .statusBar(hidden: showAppUI)
        #endif
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                RingSettingsMenu(config: config, isDarkMode: $isDarkMode, showAppUI: $showAppUI)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingSettings = false }
                        }
                    }
            }
            .presentationDetents([.height(Self.sheetDetentHeight), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.regularMaterial)
            // Reapplied here, directly on the sheet's own content — once
            // a sheet is already presented, changing `preferredColorScheme`
            // on the *presenting* view (above) doesn't reliably push back
            // down into it (that's the "toggled to Light but the sheet
            // stayed dark" bug). Setting it again on the sheet's own root
            // means it reacts to `isDarkMode` directly, no cross-
            // presentation-boundary propagation required.
            .preferredColorScheme(isDarkMode ? .dark : .light)
        }
    }

    /// Same three-tier priority as `PhoneMockupView.screen` on the Mac
    /// app: a manually-picked custom image (set from the Ring Settings
    /// sheet's Background section — real `PhotosPicker` on iOS) wins if
    /// it's on, then the bundled per-tab "App UI" screenshot when the
    /// toggle is on, then a flat page background if neither is active.
    /// Genuinely blank by default — the ring is the only thing drawn
    /// until you turn one of these on.
    ///
    /// Explicitly pinned to `size` (the same `geo.size` the rest of
    /// `body` uses) *before* `.ignoresSafeArea()`, rather than left to
    /// size itself — a resizable `Image` with `.scaledToFill()` can
    /// report a different size to the parent `ZStack` than a plain
    /// `Color` does depending on its own aspect ratio, and since `ZStack`
    /// sizes itself from its largest child before any outer `.frame()`
    /// clamps things down, that mismatch was shifting the tab bar's
    /// bottom-alignment guide specifically when the "App UI" screenshot
    /// was showing. Pinning every branch to the same explicit size first
    /// means the `ZStack` always sees the same reported size regardless
    /// of which background is active.
    @ViewBuilder
    private func background(size: CGSize) -> some View {
        Group {
            if config.backgroundImageEnabled, let image = customBackgroundImage {
                image
                    .resizable()
                    .scaledToFill()
                    .overlay(Color.black.opacity(config.backgroundDimAmount))
            } else if showAppUI {
                selectedTab.screenshotImage(dark: isDarkMode)
                    .resizable()
                    .scaledToFill()
            } else {
                DemoColors.pageBackground
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .ignoresSafeArea()
    }

    private var customBackgroundImage: Image? {
        #if os(iOS)
        guard let data = config.backgroundImageData, let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #else
        nil
        #endif
    }
}
