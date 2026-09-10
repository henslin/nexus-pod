import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Whether the previews should be running at all.
///
/// Measured on the shipped 3.6 build, sitting in the background with
/// nobody looking at it: **40% of a core, continuously**. Pausing the
/// rings took the same app to 12%, which is what identified the animation
/// as the cost rather than anything else on screen.
///
/// The work is real — a `TimelineView(.animation)` per ring, each driving
/// a SwiftUI update that AppKit answers with a layout pass over the
/// window's view tree — and none of it is worth doing for a window the
/// user has clicked away from. This is what most Mac apps do, and a click
/// brings it straight back.
///
/// Deliberately app-wide rather than per-view: the question "is anyone
/// looking at this" has one answer, and giving each preview its own
/// notification observer would be a hundred answers to the same question.
@MainActor
public final class RenderActivity: ObservableObject {
    public static let shared = RenderActivity()

    /// False while the app is in the background — previews freeze on their
    /// last frame and resume on the next click.
    @Published public private(set) var isRendering = true

    /// Non-zero while something needs the previews live regardless of
    /// focus.
    ///
    /// The particle recorder is the case that matters: it captures the
    /// app's own window frame by frame, and a preview that froze because
    /// the user clicked elsewhere mid-capture would record a still.
    private var forcedDepth = 0

    private init() {
        #if canImport(AppKit)
        let center = NotificationCenter.default
        center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(active: true) }
        }
        center.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(active: false) }
        }
        // Applied, not just recorded. Setting `isActive` alone left
        // `isRendering` at its optimistic `true`, so an app that launched
        // into the background — or whose first ring was built before it
        // came forward — rendered at full rate until the next activation
        // change happened to arrive.
        refresh(active: NSApplication.shared.isActive)
        #endif
    }

    private var isActive = true

    private func refresh(active: Bool) {
        isActive = active
        let next = active || forcedDepth > 0
        if next != isRendering { isRendering = next }
    }

    /// Keeps the previews live until the matching `endForcedRendering()`.
    public func beginForcedRendering() {
        forcedDepth += 1
        refresh(active: isActive)
    }

    public func endForcedRendering() {
        forcedDepth = max(forcedDepth - 1, 0)
        refresh(active: isActive)
    }
}
