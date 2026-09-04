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
    /// The post-update release notes — see `WhatsNewPresenter`. Same screen
    /// and same copy as the Mac app, so the two can't drift.
    @State private var showingWhatsNew = false
    @State private var selectedTab: DemoTab = .dashboard

    /// The sequence, reached from the Ring Settings sheet — see
    /// `TimelineScreen`. Bound to `config` in `.onAppear` below, which is
    /// what makes editing a step's look happen through the same settings
    /// screens as everything else rather than a separate editor.
    @StateObject private var player = TimelinePlayer()

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

    /// What the pod renders: the player's read-only playback config while
    /// a sequence is running, the live config otherwise. Identical
    /// reasoning to `PreviewTab.displayConfig` on the Mac — while paused
    /// the live config already *is* the selected step, so there's no third
    /// state to keep in sync.
    private var displayConfig: RingConfig {
        player.isPlaying ? player.playbackConfig : config
    }

    var body: some View {
        GeometryReader { geo in
            let rowWidth = geo.size.width - 32
            // `.ignoresSafeArea()` below (on the reader itself) makes `geo`
            // report the *true* full-screen size, not the safe-area-inset
            // one — see that modifier's own doc comment for why. The tab
            // bar still needs to rest above the home indicator though, so
            // its own bottom padding adds this back explicitly rather than
            // relying on the automatic safe-area layout it used to get for
            // free.
            let bottomInset = geo.safeAreaInsets.bottom

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

                    // One clock for the pod. `paused:` stops it dead when
                    // nothing is playing, so a parked timeline costs
                    // nothing — and with no timeline at all `playback(at:)`
                    // returns nil and the pod behaves exactly as it always
                    // has.
                    TimelineView(.animation(paused: !player.isPlaying)) { context in
                        TabBarPreview(
                            config: displayConfig,
                            selectedTab: $selectedTab,
                            width: rowWidth,
                            onRingTap: { showingSettings = true },
                            playback: player.playback(at: context.date)
                        )
                    }
                }
                // Fixed constants, not a fraction of `geo.size.height` —
                // the old version tried to guess the sheet's height as a
                // percentage of screen height, but `.presentationDetents`
                // measures from the true screen edge, and (now that `geo`
                // itself reports the true full-screen size too — see the
                // reader's own `.ignoresSafeArea()` below) the two finally
                // measure from the same edge. `sheetDetentHeight` below is
                // a height *we* chose for the sheet, so lining this up
                // against it is exact math, not an estimate. `bottomInset`
                // is added on top of both cases so the tab bar still clears
                // the home indicator by the same visual margin it always
                // has, now that it's no longer inset there automatically.
                .padding(.bottom, (showingSettings ? Self.sheetDetentHeight + Self.tabBarLiftMargin : Self.tabBarRestPadding) + bottomInset)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showingSettings)
                .onAppear {
                    // Sync without animating in case the loop is already
                    // active when this view first appears.
                    pillPresented = voiceConversation.isVisible
                    // Deferred to `.onAppear` for the same reason the Mac
                    // app does it: `@StateObject`s aren't guaranteed
                    // constructed until first appearance, and binding
                    // needs both objects to exist.
                    player.bind(to: config)
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
        // Makes the `GeometryReader` above report the *true* full-screen
        // size (including the status bar and home indicator strips)
        // instead of the safe-area-inset one it gets by default. Previously
        // `background(size:)` was handed the smaller, safe-area-inset size,
        // sized and `.clipped()` an Image to exactly that box, and *then*
        // tried to `.ignoresSafeArea()` just that already-fixed-size result
        // — which stretched/repositioned a crop that was never computed
        // against the true screen bounds in the first place, instead of
        // actually re-cropping against them. That mismatch is what caused
        // the "everything's pushed up, with a sliver of the image peeking
        // out above the tab bar" bug: the background was shifted relative
        // to the real screen edges. Computing everything from the true
        // full size up front (here) and adding `bottomInset` back only
        // where the tab bar actually needs it (above) fixes both at once.
        .ignoresSafeArea()
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
                RingSettingsMenu(
                    config: config,
                    isDarkMode: $isDarkMode,
                    showAppUI: $showAppUI,
                    player: player
                )
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
        .sheet(isPresented: $showingWhatsNew) {
            WhatsNewView {
                WhatsNewPresenter.markSeen()
                showingWhatsNew = false
            }
            // Not dismissible by dragging: the one button is the way out,
            // which is how the system's own post-update screens behave.
            .interactiveDismissDisabled()
            .preferredColorScheme(isDarkMode ? .dark : .light)
        }
        .task {
            showingWhatsNew = WhatsNewPresenter.shouldPresent()
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
    /// Explicitly pinned to `size` — the *true* full-screen size, since
    /// `body`'s `GeometryReader` now ignores the safe area itself (see its
    /// `.ignoresSafeArea()` call for the full story) — rather than left to
    /// size itself. A resizable `Image` with `.scaledToFill()` can report a
    /// different size to the parent `ZStack` than a plain `Color` does
    /// depending on its own aspect ratio, and since `ZStack` sizes itself
    /// from its largest child before any outer `.frame()` clamps things
    /// down, that mismatch was shifting the tab bar's bottom-alignment
    /// guide specifically when the "App UI" screenshot was showing.
    /// Pinning every branch to the same explicit size first means the
    /// `ZStack` always sees the same reported size regardless of which
    /// background is active. No `.ignoresSafeArea()` needed here anymore —
    /// `size` already *is* the full screen, so `.clipped()` alone crops
    /// each branch to exactly the real device bounds with no separate
    /// expand-after-the-fact step to get subtly out of sync with it.
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
