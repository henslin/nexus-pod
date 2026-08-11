import SwiftUI
import RingAnimatorCore

/// Small helper for `PreviewTab`'s draggable Large Preview card: adding a
/// live drag's `translation` (a `CGSize` delta) to a resting `CGPoint`
/// center is needed at both the "follow the cursor" and "where did they
/// drop it" steps.
private extension CGPoint {
    func addingTranslation(_ translation: CGSize) -> CGPoint {
        CGPoint(x: x + translation.width, y: y + translation.height)
    }
}

/// Top-level layout: one native three-column split (sidebar → content →
/// detail), the same structural pattern Mail/Notes/Xcode use. The sidebar
/// picks which tool you're in; the content and detail columns swap based on
/// that choice. This replaces an earlier version that stacked two SwiftUI
/// `TabView`s directly on top of each other (an outer Nexus/Cue
/// Library tab strip, with a second Preview/Export strip immediately below
/// it) — visually cramped and not a standard macOS pattern. A single sidebar
/// plus a toolbar-based segmented control for Nexus's
/// Preview/Export toggle reads as one coherent window instead of two
/// stacked widgets.
struct ContentView: View {
    @StateObject private var config = RingConfig()
    @StateObject private var cueStore = LEDCueStore()
    @StateObject private var presetStore = RingPresetStore()

    @State private var section: AppSection? = .ringDesigner
    @State private var designerTab: DesignerTab = .preview
    @State private var cueTab: DesignerTab = .preview
    @State private var selectedCueID: String? = LEDCueLibrary.all.first?.id
    @State private var cueSearchText: String = ""

    enum AppSection: String, CaseIterable, Identifiable, Hashable {
        case ringDesigner = "Nexus"
        case cueLibrary = "Cue Library"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .ringDesigner: return "sparkles"
            case .cueLibrary: return "books.vertical"
            }
        }
    }

    enum DesignerTab: String, CaseIterable, Identifiable {
        case preview = "Preview"
        case export = "Export Code"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $section) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(180)
        } content: {
            switch section {
            case .ringDesigner:
                SavedPresetsView(store: presetStore, config: config)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
            case .cueLibrary:
                CueListView(store: cueStore, selectedCueID: $selectedCueID, searchText: $cueSearchText)
                    .navigationSplitViewColumnWidth(min: 260, ideal: 300)
            case .none:
                ContentUnavailableView("Select a tool", systemImage: "sidebar.left")
            }
        } detail: {
            switch section {
            case .ringDesigner:
                // Preview/Export in the middle, Controls pinned to the far
                // right edge — the Figma/Sketch inspector-panel convention
                // (layers left, canvas center, properties right) rather
                // than sitting Controls right next to the Saved Animations
                // list. `designerDetail` keeps its own toolbar-hosted
                // Preview/Export segmented control regardless of where it
                // sits in this split.
                HSplitView {
                    designerDetail
                        .frame(minWidth: 420, idealWidth: 640)
                    ControlsView(config: config)
                        .frame(minWidth: 260, idealWidth: 300, maxWidth: 340)
                }
            case .cueLibrary:
                cueDetail
            case .none:
                EmptyView()
            }
        }
        .navigationTitle(section?.rawValue ?? "Ring Pod")
    }

    @ViewBuilder
    private var designerDetail: some View {
        Group {
            switch designerTab {
            case .preview:
                PreviewTab(config: config)
            case .export:
                ExportView(config: config)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $designerTab) {
                    ForEach(DesignerTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
        }
    }

    @ViewBuilder
    private var cueDetail: some View {
        if let id = selectedCueID, let cue = LEDCueLibrary.cue(id: id) {
            Group {
                switch cueTab {
                case .preview:
                    CueDetailView(cue: cue, store: cueStore)
                case .export:
                    CueExportView(cue: cue, store: cueStore)
                }
            }
            .id(cue.id)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $cueTab) {
                        ForEach(DesignerTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }
        } else {
            ContentUnavailableView("Select a cue", systemImage: "sparkles")
        }
    }
}

private struct PreviewTab: View {
    @ObservedObject var config: RingConfig
    /// Owned here rather than inside `PhoneMockupView` so both previews can
    /// share one toggle — `PhoneMockupView` gets it as a `@Binding` (it
    /// still hosts the actual picker control, and needs the raw value
    /// itself to pick the correct light/dark "App UI" screenshot asset),
    /// and `largePreview` below applies the same `.environment(\.colorScheme,
    /// ...)` override its glass reads to pick up.
    @State private var isDarkMode = true

    /// Which corner Large Preview is currently pinned to — persists across
    /// drags (see the drag gesture on `largePreviewCard` in `body`);
    /// `.topTrailing` matches where it always used to sit before it became
    /// draggable.
    @State private var previewCorner: PreviewCorner = .topTrailing
    /// Live finger-follow offset while a drag is in progress, added on top
    /// of `previewCorner`'s resting position; reset to `.zero` the instant
    /// the drag ends and the snap animation to the new corner takes over.
    @State private var previewDragTranslation: CGSize = .zero
    /// Measured off the card itself (its size varies with the "Preview
    /// size" slider in Controls) so corner math can center it correctly
    /// instead of assuming a fixed size.
    @State private var previewCardSize: CGSize = .zero

    private enum PreviewCorner {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        /// Which quadrant of the canvas a drop point falls into — this is
        /// what makes the drag "snap to nearest corner" regardless of
        /// which corner it started from.
        static func nearest(to point: CGPoint, in canvasSize: CGSize) -> PreviewCorner {
            let isTop = point.y < canvasSize.height / 2
            let isLeading = point.x < canvasSize.width / 2
            switch (isTop, isLeading) {
            case (true, true): return .topLeading
            case (true, false): return .topTrailing
            case (false, true): return .bottomLeading
            case (false, false): return .bottomTrailing
            }
        }

        /// The card's *center* point when resting in this corner — used
        /// both to render it (via `.position`) and, combined with a drag's
        /// `translation`, to figure out where it was dropped.
        func center(canvasSize: CGSize, cardSize: CGSize, margin: CGFloat) -> CGPoint {
            let x: CGFloat
            switch self {
            case .topLeading, .bottomLeading:
                x = margin + cardSize.width / 2
            case .topTrailing, .bottomTrailing:
                x = canvasSize.width - margin - cardSize.width / 2
            }
            let y: CGFloat
            switch self {
            case .topLeading, .topTrailing:
                y = margin + cardSize.height / 2
            case .bottomLeading, .bottomTrailing:
                y = canvasSize.height - margin - cardSize.height / 2
            }
            return CGPoint(x: x, y: y)
        }
    }

    private let previewCardMargin: CGFloat = 20

    /// The phone mockup now owns the whole pane — a real pannable/
    /// zoomable canvas (see `PhoneMockupView`/`ZoomableCanvas`), Figma/
    /// Sketch style, rather than a box sized to fit alongside Large
    /// Preview in a shared outer `ScrollView`. Large Preview floats on top
    /// as a draggable card instead of sharing a row with it, so both stay
    /// visible without splitting the available space — drag it to
    /// whichever of the 4 corners is out of the way (it snaps to the
    /// nearest one on release, using `.position` rather than
    /// `.overlay(alignment:)` so the drag and the snap-back both animate
    /// as plain point movement instead of fighting SwiftUI's alignment
    /// geometry).
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                PhoneMockupView(config: config, isDarkMode: $isDarkMode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                largePreviewCard
                    .background(previewCardSizeReader)
                    .position(
                        cardPosition(canvasSize: proxy.size).addingTranslation(previewDragTranslation)
                    )
                    .gesture(
                        DragGesture(minimumDistance: 3)
                            .onChanged { value in
                                previewDragTranslation = value.translation
                            }
                            .onEnded { value in
                                let dropPoint = cardPosition(canvasSize: proxy.size)
                                    .addingTranslation(value.translation)
                                previewDragTranslation = .zero
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    previewCorner = .nearest(to: dropPoint, in: proxy.size)
                                }
                            }
                    )
            }
        }
    }

    private func cardPosition(canvasSize: CGSize) -> CGPoint {
        previewCorner.center(canvasSize: canvasSize, cardSize: previewCardSize, margin: previewCardMargin)
    }

    /// An invisible `GeometryReader` behind the card, purely to measure its
    /// actual rendered size (it changes with the "Preview size" slider) so
    /// `PreviewCorner.center` can position it correctly instead of
    /// guessing a fixed size.
    private var previewCardSizeReader: some View {
        GeometryReader { cardProxy in
            Color.clear
                .onAppear { previewCardSize = cardProxy.size }
                .onChange(of: cardProxy.size) { _, newSize in previewCardSize = newSize }
        }
    }

    private var largePreviewCard: some View {
        VStack(spacing: 10) {
            Text("Large Preview").font(.caption).foregroundStyle(.secondary)
            largePreview
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }

    // The tab bar's ring pod: a 34pt ring centered in a 62pt circle (see
    // TabBarPreview.ringPod) — the proportions the large preview's margin
    // should match at any size.
    private let podDiameter: CGFloat = 34
    private let podFrameDiameter: CGFloat = 62

    /// `RingView` now scales its own stroke/glow/blur/particle sizes
    /// internally based on the `diameter` you pass it (relative to the
    /// pod's 34pt reference size — see `RingView.referenceDiameter`), so
    /// rendering directly at `previewDiameter` is both correctly
    /// proportioned *and* crisp — no `.scaleEffect` needed, which was
    /// blurry because the blur/glow/shadow layers rasterize at their
    /// original small size before a scale transform enlarges them.
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
    @ViewBuilder
    private var largePreview: some View {
        let outerDiameter = CGFloat(config.previewDiameter) * (podFrameDiameter / podDiameter)
        let ring = RingView(config: config, diameter: CGFloat(config.previewDiameter))
            .frame(width: outerDiameter, height: outerDiameter)

        // `RingView` itself now clips its own content to a circle matching
        // this frame (see `RingView.body`), so the glass here just needs to
        // supply the backing material/refraction — nothing further to clip.
        // `.environment(\.colorScheme, ...)` mirrors exactly what
        // `PhoneMockupView` applies to its own `deviceFrame`, so both
        // glass surfaces render the same appearance at once.
        Group {
            if #available(macOS 26.0, *) {
                ring.glassEffect(config.glass, in: Circle())
            } else {
                ring.background(.ultraThinMaterial, in: Circle())
            }
        }
        .environment(\.colorScheme, isDarkMode ? .dark : .light)
    }
}
