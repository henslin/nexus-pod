import SwiftUI
import RingAnimatorCore

/// Small helper for the draggable Large Preview card: adding a live drag's
/// `translation` (a `CGSize` delta) to a resting `CGPoint` center is needed
/// at both the "follow the cursor" and "where did they drop it" steps.
private extension CGPoint {
    func addingTranslation(_ translation: CGSize) -> CGPoint {
        CGPoint(x: x + translation.width, y: y + translation.height)
    }
}

/// The canvas every section previews on: a pannable, zoomable phone mockup
/// filling the pane, with the Large Preview floating over it as a card you
/// can drag into whichever corner is out of the way.
///
/// This was Nexus's, and only Nexus's. The Cue Library and Use Cases each
/// had a ring sitting in a scrolling column — no mockup, no zoom, no
/// appearance toggle — which meant the app had one good preview and two
/// approximations of it, and which one you got depended on which list you'd
/// clicked. Same stage everywhere now; the sections differ in their controls
/// and their list, which is where they actually differ.
///
/// Deliberately **not** including the timeline strip. The Cue Library has no
/// player, and giving it an empty scrubber would invent a concept that
/// section doesn't have. Each pane still puts its own strip (or nothing)
/// under the stage.
///
/// What the stage renders is whatever `config` you hand it — a resolved one.
/// While a sequence plays that's the player's read-only `playbackConfig`;
/// otherwise it's the live config, which (thanks to the Controls⇄segment
/// binding) already *is* the selected step. The stage doesn't need to know
/// which, and asking it to would give it a third state to keep in sync.
struct RingStage: View {
    @ObservedObject var config: RingConfig
    /// Non-nil only while a timeline is driving the ring.
    var playback: TimelinePlayback?
    /// Offered as an export source in the Export Animation sheet. Empty by
    /// default, which is what makes that option simply not appear.
    var timeline: RingTimeline = RingTimeline()

    /// Every piece of stage state that should outlive this view being torn
    /// down and rebuilt — zoom, pan, appearance, which corner the card is
    /// parked in. Owned by `ContentView` and shared by all three sections;
    /// see `StageState` for why it lives there rather than here, and for why
    /// hoisting the state was the cheap way to get what hoisting the whole
    /// stage would have given.
    @ObservedObject var state: StageState

    /// Live finger-follow offset while a drag is in progress, added on top
    /// of the resting corner position and reset to `.zero` the instant the
    /// drag ends. Genuinely transient — a drag can't still be in progress
    /// across a section switch — so this one stays local.
    @State private var previewDragTranslation: CGSize = .zero

    private let previewCardMargin: CGFloat = 20
    /// Fixed and known ahead of time (unlike the expanded card, which is
    /// measured — see `previewCardSizeReader`) since it's just a plain
    /// circular button whose size we control outright. Using a constant
    /// here instead of measuring it means collapsing/expanding can change
    /// `isPreviewCollapsed` and reposition in the very same animated
    /// transaction with no dependency on a `GeometryReader` remeasurement
    /// landing before the animation reads it — the same class of bug the
    /// drag-snap fix below just worked around.
    private let collapsedPreviewSize = CGSize(width: 44, height: 44)

    /// The phone mockup owns the whole pane — a real pannable/zoomable
    /// canvas (see `PhoneMockupView`/`ZoomableCanvas`), Figma/Sketch style,
    /// rather than a box sized to fit alongside Large Preview in a shared
    /// outer `ScrollView`. Large Preview floats on top as a draggable card
    /// instead of sharing a row with it, so both stay visible without
    /// splitting the available space — drag it to whichever of the 4
    /// corners is out of the way (it snaps to the nearest one on release,
    /// using `.position` rather than `.overlay(alignment:)` so the drag and
    /// the snap-back both animate as plain point movement instead of
    /// fighting SwiftUI's alignment geometry).
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                PhoneMockupView(
                    config: config,
                    isDarkMode: $state.isDarkMode,
                    deviceFinish: $state.deviceFinish,
                    playback: playback,
                    timeline: timeline,
                    stageState: state
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                largePreviewCard
                    .position(
                        cardPosition(canvasSize: proxy.size).addingTranslation(previewDragTranslation)
                    )
                    // .simultaneousGesture rather than .gesture: the
                    // collapse/expand button lives inside largePreviewCard,
                    // and .gesture claims priority over its child views'
                    // own gestures (including a Button's tap), which would
                    // make the button unreliable to click. Simultaneous
                    // recognition lets the drag and the button's tap each
                    // resolve independently -- SwiftUI's Button already
                    // cancels its own tap if the pointer moves enough to
                    // count as a drag, so this doesn't risk double-firing.
                    .simultaneousGesture(
                        // minimumDistance: 0 rather than 3 — this gesture
                        // now also has to catch plain, near-motionless
                        // clicks on the collapsed button (see the
                        // isPreviewCollapsed check in onEnded below), which
                        // a minimumDistance of 3 would simply never
                        // recognize at all.
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                previewDragTranslation = value.translation
                            }
                            .onEnded { value in
                                let dropPoint = cardPosition(canvasSize: proxy.size)
                                    .addingTranslation(value.translation)
                                let dragDistance = (
                                    value.translation.width * value.translation.width
                                    + value.translation.height * value.translation.height
                                ).squareRoot()
                                // Both state changes belong in the *same*
                                // animated transaction: resetting the drag
                                // translation and switching corners
                                // together lets SwiftUI interpolate
                                // directly from "wherever the cursor let
                                // go" to "the new corner's resting spot"
                                // in one continuous move. Resetting the
                                // translation outside (or before) the
                                // withAnimation block snaps the card back
                                // to the *old* corner's resting position
                                // first, un-animated, and only then
                                // animates from there to the new corner --
                                // a visible jump-then-slide instead of one
                                // smooth motion.
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    // Collapsed state has no `Button` of its
                                    // own anymore (see
                                    // `collapsedPreviewButton`) — a real
                                    // macOS `Button` there didn't reliably
                                    // cancel its own tap just because this
                                    // sibling drag gesture also recognized
                                    // the same pointer movement, so both
                                    // fired on release: the card snapped to
                                    // the nearest corner *and* the button's
                                    // tap flipped `isPreviewCollapsed` back
                                    // to false, undoing the collapse on
                                    // every single drag. Treating a
                                    // near-motionless release as "tap to
                                    // expand" here, inside this one gesture,
                                    // removes that race instead of trying
                                    // to make two independent recognizers
                                    // agree.
                                    if state.isPreviewCollapsed && dragDistance < 6 {
                                        state.isPreviewCollapsed = false
                                    }
                                    state.previewCorner = StageState.PreviewCorner.nearest(to: dropPoint, in: proxy.size)
                                    previewDragTranslation = .zero
                                }
                            }
                    )
            }
        }
    }

    private func cardPosition(canvasSize: CGSize) -> CGPoint {
        let cardSize = state.isPreviewCollapsed ? collapsedPreviewSize : state.previewCardSize
        return state.previewCorner.center(canvasSize: canvasSize, cardSize: cardSize, margin: previewCardMargin)
    }

    /// An invisible `GeometryReader` behind the card, purely to measure its
    /// actual rendered size (it changes with the "Preview size" slider) so
    /// `PreviewCorner.center` can position it correctly instead of
    /// guessing a fixed size.
    private var previewCardSizeReader: some View {
        GeometryReader { cardProxy in
            Color.clear
                .onAppear { state.previewCardSize = cardProxy.size }
                .onChange(of: cardProxy.size) { _, newSize in state.previewCardSize = newSize }
        }
    }

    /// Switches between the full card and the small collapsed button —
    /// `largePreviewCollapseButton`'s tap target lives *inside* the
    /// expanded card (top-trailing, next to the label) so collapsing is
    /// reachable without hunting for a separate control; the collapsed
    /// state's entire button doubles as the expand target.
    @ViewBuilder
    private var largePreviewCard: some View {
        if state.isPreviewCollapsed {
            collapsedPreviewButton
                .frame(width: collapsedPreviewSize.width, height: collapsedPreviewSize.height)
        } else {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Text("Large Preview").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    largePreviewCollapseButton
                }
                // Without this, the Spacer above has no width to actually
                // be constrained by: largePreviewCard sits directly in a
                // ZStack alongside PhoneMockupView's .frame(maxWidth:
                // .infinity, maxHeight: .infinity), so the *proposed*
                // width flowing down to this HStack is the whole canvas,
                // and the Spacer greedily fills it -- stretching the
                // header (and the card behind it) edge-to-edge instead of
                // hugging the ring below it. Pinning the header to the
                // ring's own width keeps the collapse button at the
                // card's actual top-right corner.
                .frame(width: previewOuterDiameter)
                largePreview
            }
            .padding(16)
            .glassBackground(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            .background(previewCardSizeReader)
        }
    }

    private var largePreviewCollapseButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                state.isPreviewCollapsed = true
            }
        } label: {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .ringGlassButtonStyle()
        .help("Collapse Large Preview")
    }

    /// The collapsed state: just the ring itself, small and round, so it
    /// still reads as "the large preview, tucked away" rather than an
    /// unrelated icon — tapping anywhere on it expands the card back.
    ///
    /// Deliberately *not* a `Button` — expand-on-tap is instead handled by
    /// the drag gesture on `largePreviewCard` in `body` (see its `onEnded`),
    /// which is what makes drag-to-reposition and tap-to-expand agree on
    /// what happened instead of racing each other. `.contentShape` keeps
    /// the whole circle (not just the ring stroke) hit-testable for that
    /// gesture, matching what a real `Button` gave it for free before.
    private var collapsedPreviewButton: some View {
        glassRing(outerDiameter: collapsedPreviewSize.width, ringDiameter: collapsedPreviewSize.width * 0.6)
            .contentShape(Circle())
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            .help("Show Large Preview")
    }

    // The tab bar's ring pod: a 34pt ring centered in a 62pt circle (see
    // TabBarPreview.ringPod) — the proportions the large preview's margin
    // should match at any size.
    private let podDiameter: CGFloat = 34
    private let podFrameDiameter: CGFloat = 62

    /// `RingView` scales its own stroke/glow/blur/particle sizes internally
    /// based on the `diameter` you pass it (relative to the pod's 34pt
    /// reference size — see `RingView.referenceDiameter`), so rendering
    /// directly at `previewDiameter` is both correctly proportioned *and*
    /// crisp — no `.scaleEffect` needed, which was blurry because the
    /// blur/glow/shadow layers rasterize at their original small size
    /// before a scale transform enlarges them.
    ///
    /// The surrounding circle's margin is scaled by the same ratio as the
    /// pod's own frame-to-ring ratio, so the margin looks consistent with
    /// the pod at every preview size instead of the old fixed +40pt
    /// padding. It's real Liquid Glass now (`config.glass`, same as
    /// `TabBarPreview.ringPodGlass`) rather than a flat black circle, so
    /// this preview matches what the pod actually looks like — including
    /// responding to the same Light/Dark toggle the phone mockup has
    /// (`isDarkMode` above, shared via `@Binding` with `PhoneMockupView`)
    /// instead of a plain dark backdrop that only happened to look okay
    /// behind bright rings.
    ///
    /// "Background image" (`RingConfig.backgroundImageEnabled`) does *not*
    /// apply here — it's specifically a manual custom-PNG option for the
    /// iPhone mockup's screen content (see `PhoneMockupView.screen`), for
    /// testing arbitrary reference images beyond the bundled "App UI" set.
    /// This preview stays exactly the ring, always.
    private var largePreview: some View {
        glassRing(
            outerDiameter: previewOuterDiameter,
            ringDiameter: CGFloat(config.previewDiameter)
        )
    }

    /// Also used by `largePreviewCard`'s header row (see the `.frame`
    /// comment there) to pin the collapse button to the ring's actual
    /// right edge instead of the whole canvas's.
    private var previewOuterDiameter: CGFloat {
        CGFloat(config.previewDiameter) * (podFrameDiameter / podDiameter)
    }

    /// Shared by `largePreview` (sized off the "Preview size" slider) and
    /// `collapsedPreviewButton` (a small fixed size instead) — factored out
    /// so the collapsed button is a genuine miniature of the same glass
    /// ring rather than a separate icon that could drift out of sync with
    /// it.
    ///
    /// `RingView` itself clips its own content to a circle matching its
    /// frame (see `RingView.body`), so the glass here just needs to supply
    /// the backing material/refraction — nothing further to clip.
    /// `.environment(\.colorScheme, ...)` mirrors exactly what
    /// `PhoneMockupView` applies to its own `deviceFrame`, so both glass
    /// surfaces render the same appearance at once.
    @ViewBuilder
    private func glassRing(outerDiameter: CGFloat, ringDiameter: CGFloat) -> some View {
        let ring = RingView(config: config, diameter: ringDiameter, overrideElapsed: playback?.elapsed)
            .frame(width: outerDiameter, height: outerDiameter)
            .opacity(playback?.opacity ?? 1)

        Group {
            if #available(macOS 26.0, *) {
                ring.glassEffect(config.glass, in: Circle())
            } else {
                ring.background(.ultraThinMaterial, in: Circle())
            }
        }
        .environment(\.colorScheme, state.isDarkMode ? .dark : .light)
    }
}
