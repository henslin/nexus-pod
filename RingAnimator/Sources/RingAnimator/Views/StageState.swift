import SwiftUI
import RingAnimatorCore

/// Everything about the stage that belongs to *you* rather than to what
/// you're looking at: how far you've zoomed in, where you've panned to,
/// which corner Large Preview is parked in, and whether you're previewing
/// light or dark.
///
/// Owned by `ContentView` and shared by all three sections, which is what
/// makes part B of the stage work small. Sections swap through a `switch`,
/// and a `switch` gives each branch its own identity, so SwiftUI tears the
/// stage down and rebuilds it on every section change. Hoisting the whole
/// stage into `ContentView` would fix that too, but only by first hoisting
/// every section's editing state — the cue's parameters, the use case's
/// config and its player — to keep the one stage fed. Hoisting the state
/// the stage *keeps* gets the same result: the view can be rebuilt as often
/// as SwiftUI likes and it comes back exactly as you left it.
///
/// `ZoomableCanvas` is the reason this can't just be `@State` somewhere.
/// Its pan and zoom live in a real `NSScrollView`, with nothing for SwiftUI
/// to restore once the `NSViewRepresentable` is recreated — so the values
/// have to be read back out of AppKit as they change and pushed back in
/// when the view is rebuilt.
@MainActor
final class StageState: ObservableObject {
    /// Not `@Published`. It's written continuously during a pinch or a
    /// scroll — publishing would invalidate the whole stage on every frame
    /// of a gesture, and nothing in SwiftUI needs to *react* to it. It's
    /// storage, read once when the canvas is rebuilt.
    var magnification: CGFloat?
    var scrollOrigin: CGPoint?

    /// These do drive rendering, so they publish.
    @Published var isDarkMode = true
    /// Which iPhone the canvas mockup wears. Lives here, with the rest of
    /// the shared stage state, so switching sections doesn't switch phones.
    @Published var deviceFinish: AnimationExporter.DeviceFinish = .deepBlue
    @Published var previewCorner: PreviewCorner = .topTrailing
    @Published var isPreviewCollapsed = false
    /// Measured off the card (its size varies with the "Preview size"
    /// slider) so corner math can center it instead of assuming a size.
    @Published var previewCardSize: CGSize = .zero

    enum PreviewCorner {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        /// Which quadrant of the canvas a drop point falls into — this is
        /// what makes the drag "snap to nearest corner" regardless of which
        /// corner it started from.
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

        /// The card's *center* point when resting in this corner — used both
        /// to render it (via `.position`) and, combined with a drag's
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
}
