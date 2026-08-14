import SwiftUI

/// The same Liquid Glass "Large Preview" card Nexus's own preview canvas
/// uses (`ContentView`'s `PreviewTab.largePreviewCard`/`glassRing`) —
/// extracted here so Cue Library (`CueDetailView`) and Use Cases
/// (`UseCaseDetailView`) can present their own live preview in identical
/// chrome instead of each inventing its own plain box, so all three read
/// as "the same app" rather than three slightly different preview
/// treatments.
///
/// Nexus's own `PreviewTab` keeps its existing, independent
/// implementation rather than switching to this one — it also needs
/// draggable-to-corner/collapse behavior this deliberately doesn't have
/// (per the request that led to this file: reuse the box/container, no
/// need for it to be drag-and-drop-able), and touching that already-
/// verified view purely to deduplicate a shared box isn't worth the risk
/// (same reasoning `glassBackground(in:)`'s own doc comment gives for not
/// retrofitting `ControlsView`'s private copy).
///
/// Two glass surfaces, same as Nexus's: the outer rounded-rect card (via
/// `glassBackground(in:)`, already shared with Nexus) and an inner
/// circular "pod" directly behind the preview content itself, sized at
/// the same ratio (62/34) `TabBarPreview`'s ring pod and Nexus's own
/// Large Preview use. Both use plain, untinted glass here rather than a
/// per-item `Glass` value — Cue Library's `LEDCueParameters` has no
/// Liquid Glass fields to draw one from at all, so a neutral, always-
/// consistent pod (rather than tinted for one caller and plain for
/// another) is what actually reads as "the same box" across all three
/// sections, rather than three subtly different ones.
public struct LargePreviewCard<RingContent: View>: View {
    let title: String?
    let diameter: CGFloat
    let isDarkMode: Bool
    @ViewBuilder let ringContent: () -> RingContent

    /// - Parameters:
    ///   - title: A small caption above the pod, matching Nexus's own
    ///     "Large Preview" label. `nil` (the default) omits it — the right
    ///     call whenever this card sits under its own header elsewhere on
    ///     the pane (`CueDetailView`/`UseCaseDetailView` both already show
    ///     the cue/use-case name above), so the card doesn't carry a
    ///     redundant second caption.
    ///   - diameter: The ring's own diameter — the pod is sized up from
    ///     this at the same fixed ratio Nexus's pod/ring proportions use,
    ///     not a caller-supplied outer size, so every call site's pod
    ///     reads as genuinely the same shape at any scale.
    ///   - isDarkMode: Applied via `.environment(\.colorScheme:)` to the
    ///     pod only, matching `PreviewTab.glassRing` — defaults to `true`
    ///     since neither `CueDetailView` nor `UseCaseDetailView` currently
    ///     track a light/dark toggle of their own the way Nexus's preview
    ///     pane does.
    public init(
        title: String? = nil,
        diameter: CGFloat,
        isDarkMode: Bool = true,
        @ViewBuilder ringContent: @escaping () -> RingContent
    ) {
        self.title = title
        self.diameter = diameter
        self.isDarkMode = isDarkMode
        self.ringContent = ringContent
    }

    // The tab bar's ring pod: a 34pt ring centered in a 62pt circle (see
    // `TabBarPreview.ringPod`) — the same proportion `PreviewTab.largePreview`
    // scales its own margin by, reused verbatim here.
    private let podDiameter: CGFloat = 34
    private let podFrameDiameter: CGFloat = 62

    private var outerDiameter: CGFloat {
        diameter * (podFrameDiameter / podDiameter)
    }

    public var body: some View {
        VStack(spacing: 10) {
            if let title {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: outerDiameter, alignment: .leading)
            }
            glassPod
        }
        .padding(16)
        .glassBackground(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }

    @ViewBuilder
    private var glassPod: some View {
        let sized = ringContent()
            .frame(width: outerDiameter, height: outerDiameter)
        Group {
            if #available(macOS 26.0, iOS 26.0, *) {
                sized.glassEffect(.regular, in: Circle())
            } else {
                sized.background(.ultraThinMaterial, in: Circle())
            }
        }
        .environment(\.colorScheme, isDarkMode ? .dark : .light)
    }
}
