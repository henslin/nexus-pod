import SwiftUI
import RingAnimatorCore

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

    var body: some View {
        GeometryReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                HStack(alignment: .center, spacing: 48) {
                    VStack(spacing: 10) {
                        Text("iPhone 17 Pro Preview").font(.caption).foregroundStyle(.secondary)
                        PhoneMockupView(config: config, isDarkMode: $isDarkMode)
                    }

                    VStack(spacing: 10) {
                        Text("Large Preview").font(.caption).foregroundStyle(.secondary)
                        largePreview
                    }
                }
                .padding(40)
                // A frame at least as big as the viewport, centered by
                // default — so when content is smaller than the window it
                // sits dead-center both ways, and when it's larger the
                // ScrollView takes over instead of clipping anything.
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
            }
        }
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
