import SwiftUI
import AppKit
import RingAnimatorCore

/// Hosts SwiftUI `content` inside a real `NSScrollView` with
/// `allowsMagnification` turned on — the correct, Apple-supported
/// trackpad pinch-to-zoom mechanism (the same one Preview/Photos/Xcode
/// use). This was previously blocked for a long time by a completely
/// unrelated bug: the app itself never called `NSApp.activate()` when
/// launched from Xcode's debugger, so it never became the truly active
/// app at all — no gesture, keystroke, or click-driven focus change ever
/// reached it (see `RingAnimatorApp.swift`'s `AppDelegate` for the actual
/// fix). Once that was fixed, this mechanism — which was always
/// structurally correct — started receiving real gestures.
///
/// The live "150%"-style zoom badge is a plain SwiftUI `overlay`, not an
/// `NSView` added as a subview of the scroll view. An earlier version
/// tried the latter (a layer-backed `NSView` pinned via Auto Layout
/// constraints to the scroll view's trailing/bottom anchors) and it
/// silently never appeared — logging showed its frame stuck at
/// `(0, 0, 0, 0)` forever, even long after layout should have settled.
/// `NSScrollView` actively manages the layout of its own direct subviews
/// (clip view, scrollers) and doesn't reliably honor Auto Layout
/// constraints on arbitrary subviews added via plain `addSubview` the way
/// a normal `NSView` would — the supported mechanism for that is
/// `addFloatingSubview(for:)`, which has its own frame/autoresizing-mask
/// quirks. Routing the zoom percentage out through the `Coordinator` to
/// plain SwiftUI `@State` and rendering the badge as a SwiftUI overlay
/// sidesteps all of that and lets ordinary SwiftUI layout size it.
struct ZoomableCanvas<Content: View>: View {
    let contentSize: CGSize
    let minMagnification: CGFloat
    let maxMagnification: CGFloat
    let restMagnification: CGFloat
    /// Where the viewport was when this canvas was last torn down, and
    /// where to report it back to. Optional so a canvas that doesn't need
    /// to survive being rebuilt can leave it out — see `StageState` for why
    /// the one in `RingStage` does.
    var viewport: StageState?
    @ViewBuilder var content: () -> Content

    @State private var zoomPercent: Int = 100
    @State private var badgeVisible = false
    @State private var hideBadgeWorkItem: DispatchWorkItem?

    /// Written explicitly (rather than relying on the synthesized
    /// memberwise init) so the trailing-closure call site in
    /// `PhoneMockupView` unambiguously binds to `content` regardless of
    /// the `@State` properties declared after it.
    init(
        contentSize: CGSize,
        minMagnification: CGFloat,
        maxMagnification: CGFloat,
        restMagnification: CGFloat,
        viewport: StageState? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.contentSize = contentSize
        self.minMagnification = minMagnification
        self.maxMagnification = maxMagnification
        self.restMagnification = restMagnification
        self.viewport = viewport
        self.content = content
    }

    var body: some View {
        ZoomableScrollRepresentable(
            contentSize: contentSize,
            minMagnification: minMagnification,
            maxMagnification: maxMagnification,
            restMagnification: restMagnification,
            viewport: viewport,
            onPercentChange: { percent in
                zoomPercent = percent
            },
            onMagnifyBegin: {
                hideBadgeWorkItem?.cancel()
                withAnimation(.easeOut(duration: 0.12)) { badgeVisible = true }
            },
            onMagnifyEnd: {
                scheduleHideBadge()
            },
            content: content
        )
        .overlay(alignment: .bottomTrailing) {
            Text("\(zoomPercent)%")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(14)
                .opacity(badgeVisible ? 1 : 0)
                .allowsHitTesting(false)
        }
    }

    private func scheduleHideBadge() {
        hideBadgeWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.35)) { badgeVisible = false }
        }
        hideBadgeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
    }
}

/// The `NSViewRepresentable` half of `ZoomableCanvas` — everything AppKit,
/// with no SwiftUI state of its own. Reports zoom changes and live-magnify
/// start/end back up to `ZoomableCanvas` via plain closures.
private struct ZoomableScrollRepresentable<Content: View>: NSViewRepresentable {
    let contentSize: CGSize
    let minMagnification: CGFloat
    let maxMagnification: CGFloat
    let restMagnification: CGFloat
    let viewport: StageState?
    let onPercentChange: (Int) -> Void
    let onMagnifyBegin: () -> Void
    let onMagnifyEnd: () -> Void
    @ViewBuilder var content: () -> Content

    private var sizedContent: AnyView {
        AnyView(content().frame(width: contentSize.width, height: contentSize.height))
    }

    func makeNSView(context: Context) -> NSScrollView {
        let hostingView = NSHostingView(rootView: sizedContent)
        hostingView.frame = CGRect(origin: .zero, size: contentSize)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.allowsMagnification = true
        scrollView.minMagnification = minMagnification
        scrollView.maxMagnification = maxMagnification
        scrollView.contentView = CenteringClipView()
        // Restored before `documentView` is set, so the clip view lays the
        // content out at the right scale first time rather than at rest and
        // then jumping.
        scrollView.magnification = viewport?.magnification ?? restMagnification
        scrollView.documentView = hostingView
        if let origin = viewport?.scrollOrigin {
            // After `documentView`: the clip view has no scrollable extent
            // to move within until it has content, so scrolling before this
            // silently clamps back to zero.
            scrollView.contentView.scroll(to: origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            // And again once layout has actually happened. At this point the
            // scroll view has a document view but not necessarily its final
            // frame, and `CenteringClipView` re-centers whatever it's given
            // until the content is genuinely larger than the viewport — so
            // the first call is frequently clamped straight back to the
            // centered position. One deferred repeat lands after the first
            // layout pass; it runs only at creation, so it can't fight a
            // scroll the user is in the middle of.
            DispatchQueue.main.async {
                scrollView.contentView.scroll(to: origin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }

        let doubleClick = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleClick)
        )
        doubleClick.numberOfClicksRequired = 2
        scrollView.addGestureRecognizer(doubleClick)

        context.coordinator.hostingView = hostingView
        context.coordinator.scrollView = scrollView
        context.coordinator.restMagnification = restMagnification
        context.coordinator.onPercentChange = onPercentChange
        context.coordinator.onMagnifyBegin = onMagnifyBegin
        context.coordinator.onMagnifyEnd = onMagnifyEnd
        context.coordinator.viewport = viewport
        context.coordinator.observeMagnification(of: scrollView)
        context.coordinator.observeScrolling(of: scrollView)

        let coordinator = context.coordinator
        NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveMagnifyNotification,
            object: scrollView,
            queue: .main
        ) { [weak coordinator] _ in
            MainActor.assumeIsolated { coordinator?.magnifyDidBegin() }
        }
        NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveMagnifyNotification,
            object: scrollView,
            queue: .main
        ) { [weak coordinator] _ in
            MainActor.assumeIsolated { coordinator?.magnifyDidEnd() }
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.viewport = viewport
        context.coordinator.restMagnification = restMagnification
        context.coordinator.onPercentChange = onPercentChange
        context.coordinator.onMagnifyBegin = onMagnifyBegin
        context.coordinator.onMagnifyEnd = onMagnifyEnd
        context.coordinator.hostingView?.rootView = sizedContent
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// `@MainActor` explicitly — every touch of `scrollView.magnification`/
    /// `.animator()` here needs to be main-actor-isolated; gesture-
    /// recognizer target-action, `NSKeyValueObservation`, and this file's
    /// `NotificationCenter` observers (registered with `queue: .main`) all
    /// guarantee that in practice, so this annotation just tells the
    /// compiler what's already true at runtime.
    @MainActor
    final class Coordinator: NSObject {
        weak var hostingView: NSHostingView<AnyView>?
        weak var scrollView: NSScrollView?
        var viewport: StageState?
        var restMagnification: CGFloat = 1
        var onPercentChange: (Int) -> Void = { _ in }
        var onMagnifyBegin: () -> Void = {}
        var onMagnifyEnd: () -> Void = {}

        private var magnificationObservation: NSKeyValueObservation?

        /// Live, real-time zoom-percentage readout — `NSKeyValueObservation`
        /// on `magnification` fires continuously throughout a pinch
        /// gesture (not just at the start/end), which is what makes the
        /// badge track your fingers instead of just flashing a final
        /// number.
        func observeMagnification(of scrollView: NSScrollView) {
            // Deferred to the next run-loop turn: this is called from
            // makeNSView, which runs *during* a SwiftUI view update, and
            // synchronously mutating the @State this drives from inside
            // that update is invalid (SwiftUI logs "Modifying state during
            // view update, this will cause undefined behavior"). The
            // magnification hasn't changed from `zoomPercent`'s own 100
            // default at this point anyway -- this call exists so a
            // non-default `restMagnification` still gets reflected if the
            // badge is ever shown before the first real magnify.
            let initialPercent = percentage(for: scrollView.magnification)
            DispatchQueue.main.async { [onPercentChange] in
                onPercentChange(initialPercent)
            }
            magnificationObservation = scrollView.observe(\.magnification, options: [.new]) { [weak self] scrollView, _ in
                // The whole body, not just the viewport write. AppKit posts
                // this on the main thread — a magnification only changes
                // because someone pinched — so `assumeIsolated` states that
                // rather than hopping, which would land the badge a frame
                // behind the gesture driving it. The viewport write was
                // already doing this; the two lines above it were reaching
                // for main-actor state from outside, which is the same
                // assumption made silently.
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.onPercentChange(self.percentage(for: scrollView.magnification))
                    self.viewport?.magnification = scrollView.magnification
                }
            }
        }

        /// Records the pan position as it changes, so it can be put back
        /// when this canvas is rebuilt.
        ///
        /// A clip view doesn't post bounds notifications unless asked, and
        /// the ask has to come before the observer or the first pan goes
        /// unrecorded.
        func observeScrolling(of scrollView: NSScrollView) {
            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true
            // Token deliberately not retained for later removal, matching
            // the two live-magnify observers registered in `makeNSView`:
            // the closure holds the coordinator weakly, so once it's gone
            // this does nothing, and a nonisolated `deinit` can't touch a
            // non-Sendable token anyway.
            NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let scrollView = self.scrollView else { return }
                    self.viewport?.scrollOrigin = scrollView.contentView.bounds.origin
                }
            }
        }


        func magnifyDidBegin() {
            onMagnifyBegin()
        }

        func magnifyDidEnd() {
            onMagnifyEnd()
        }

        /// Animates back to actual size — mirrors what a `resetZoom()`
        /// helper used to do by hand when zoom was tracked in SwiftUI
        /// `@State`; now it's just telling the scroll view itself to
        /// animate its own `magnification` back down.
        @objc func handleDoubleClick() {
            guard let scrollView else { return }
            onMagnifyBegin()
            NSAnimationContext.runAnimationGroup { animationContext in
                animationContext.duration = 0.3
                animationContext.allowsImplicitAnimation = true
                scrollView.animator().magnification = restMagnification
            }
            onMagnifyEnd()
        }

        private func percentage(for magnification: CGFloat) -> Int {
            Int((magnification * 100).rounded())
        }
    }
}

/// A stock `NSClipView` sits the document view at its bounds origin and
/// leaves it there — fine while the document exactly fills the viewport
/// (magnification 1, which is how `deviceFrame` is sized here, with zero
/// margin), but the moment magnification moves off 1 in either direction
/// the phone mockup would slide into a single corner instead of staying
/// centered: zoomed out, it'd sit pinned to one edge with all the empty
/// space on the other side; zoomed in, panning back to the start would
/// land off-center instead of back in the middle. Overriding
/// `constrainBoundsRect` to re-center whenever the document is smaller
/// than the visible bounds — and to center the *initial* over-sized case
/// too — keeps zooming feeling like Preview/Photos in either direction.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let documentFrame = documentView.frame

        if documentFrame.width < proposedBounds.width {
            rect.origin.x = (documentFrame.width - proposedBounds.width) / 2
        }
        if documentFrame.height < proposedBounds.height {
            rect.origin.y = (documentFrame.height - proposedBounds.height) / 2
        }
        return rect
    }
}
