import SwiftUI

/// Mirrors the native iOS 26/27 tab bar: a floating Liquid Glass capsule
/// with equal-width icon+label items — black glyph/label on the selected
/// item over a 76pt-wide pill, `.secondary` on the rest — plus a detached
/// glass "pod" for the AI ring.
/// That split is the same pattern Apple's own apps use for a trailing
/// accessory tab (e.g. Search) that floats apart from the main bar.
///
/// Public/shared (moved here from the Mac-only `RingAnimator` target) so
/// both the Mac design tool's phone mockup *and* the real iOS app
/// (`RingAnimatoriOS`) render the exact same tab bar + ring pod — one
/// component, not two hand-kept-in-sync copies. On macOS it's still only a
/// tap-only preview (see the doc comment on `onRingTap` below); the real
/// iOS app is where it's genuinely interactive and gets real swipe/gesture
/// feel from being hosted directly in a real window instead of a simulated
/// phone frame.
///
/// This package's `Package.swift` can't declare a macOS 26/iOS 26 minimum
/// — neither `.v26` nor `.v27` exist as `SupportedPlatform` cases in this
/// Xcode beta's `PackageDescription`, regardless of the declared
/// swift-tools-version — so every real Glass API call here needs an
/// explicit `#available(iOS 26.0, macOS 26.0, *)` check (both platforms
/// named — an unlisted platform falls back to *its* declared package
/// minimum, iOS 17 here, not "always available") with a pre-Glass material
/// fallback for the compiler to accept it. (The separate iOS Xcode project
/// doesn't have this problem for its *own* code — its deployment target is
/// set directly in project settings, not through a Package.swift platforms
/// list — but this file compiles as part of the package, not the app
/// target, so it's still bound by the package's own declared minimum. On
/// iOS this always takes the real-Glass branch regardless.)
public struct TabBarPreview: View {
    @ObservedObject var config: RingConfig
    @Binding var selectedTab: DemoTab
    var width: CGFloat
    /// Called when the ring pod itself is tapped — `nil` (the default)
    /// keeps the pod purely decorative, which is what the Mac app's phone
    /// mockup wants (nothing to navigate to from there). `RingAnimatoriOS`
    /// passes a real closure that opens the Ring settings sheet, making the
    /// pod double as both "what the ring looks like" and "the button that
    /// configures it" — the same one-object-does-both relationship a real
    /// Siri/Assistant glyph has with its own settings.
    var onRingTap: (() -> Void)?

    /// Timeline playback, when a sequence is driving the pod instead of the
    /// live config's own infinite loop. `nil` (the default) is the original
    /// behavior in full: `RingView` runs off its own `TimelineView`
    /// clock and nothing is dimmed.
    ///
    /// Threaded through as a value rather than read from a shared object so
    /// this stays a pure function of its inputs — the same reason
    /// `RingView` takes `overrideElapsed` instead of reaching for a clock.
    var playback: TimelinePlayback?

    /// The image for `PodContent.photo`.
    ///
    /// **This is the seam the host app will eventually plug into.** Today
    /// nothing passes it and `.photo` draws an obvious placeholder, which
    /// is deliberate: the point of this pass is choosing what the pod
    /// should show, and a placeholder that reads as "host supplies this"
    /// is more honest at that stage than a bundled stock avatar that
    /// flatters the design. When a look is chosen, this parameter is
    /// where the real content arrives — widen it then, not now.
    var podImage: Image?

    public init(
        config: RingConfig,
        selectedTab: Binding<DemoTab>,
        width: CGFloat = 340,
        onRingTap: (() -> Void)? = nil,
        playback: TimelinePlayback? = nil,
        podImage: Image? = nil
    ) {
        self.config = config
        self._selectedTab = selectedTab
        self.width = width
        self.onRingTap = onRingTap
        self.playback = playback
        self.podImage = podImage
    }

    /// Drives the selected-tab pill's slide between items.
    @Namespace private var selectionNamespace

    @Environment(\.colorScheme) private var colorScheme

    /// Light mode: every glyph/label is black, selected or not. Dark mode:
    /// the selected item is white; unselected glyphs and labels use two
    /// slightly different grays (glyph #C6C6CF, label #E8E8EB).
    private func iconColor(isSelected: Bool) -> Color {
        guard colorScheme == .dark else { return .black }
        return isSelected ? .white : Color(hex: "#C6C6CF")
    }

    private func textColor(isSelected: Bool) -> Color {
        guard colorScheme == .dark else { return .black }
        return isSelected ? .white : Color(hex: "#E8E8EB")
    }

    public var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    tabBarCapsule
                        .frame(maxWidth: .infinity)
                        .glassEffect(config.glass, in: Capsule())

                    ringPodStack
                }
            }
            .frame(width: width)
        } else {
            HStack(spacing: 10) {
                tabBarCapsule
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial, in: Capsule())

                ringPodStack
            }
            .frame(width: width)
        }
    }

    private var tabBarCapsule: some View {
        HStack(spacing: 0) {
            ForEach(DemoTab.allCases) { tab in
                tabItem(tab)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 54)
    }

    /// The ring pod, with a duplicate ring behind it: same 34pt diameter
    /// as the front ring, and centered exactly on it — a `ZStack` centers
    /// its layers by default, so no manual offset math is needed to line
    /// the two up. The duplicate is added to the stack *before* the front
    /// ring/glass layer, so it sits behind the Liquid Glass material and
    /// gets genuinely refracted by it, rather than sitting on top.
    private var ringPodStack: some View {
        ZStack {
            ringPodBackgroundDuplicate
            ringPodGlass
        }
    }

    private var ringPodBackgroundDuplicate: some View {
        podContent(drawsDiffuser: false)
            .frame(width: CGFloat(RingConfig.tabBarPodDiameter), height: CGFloat(RingConfig.tabBarPodDiameter))
            .blur(radius: 4)
            // Multiplied into the existing 0.8, not replacing it — this
            // layer is deliberately dimmer than the pod itself (see
            // `ringPodStack`), and a timeline fade should scale that
            // relationship rather than flatten it.
            .opacity(0.8 * (playback?.opacity ?? 1))
    }

    @ViewBuilder
    private var ringPodGlass: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            // `podGlass`, not `glass` — the pod carries the tinted fill;
            // the bar keeps the shared material.
            ringPodTappable.glassEffect(config.podGlass, in: Capsule())
        } else {
            ringPodTappable.background(.ultraThinMaterial, in: Capsule())
        }
    }

    /// Wraps `ringPod` in a real `Button` only when `onRingTap` is
    /// supplied — see that property's doc comment. `.buttonStyle(.plain)`
    /// keeps it looking exactly like the undecorated ring when there's
    /// nothing to tap, and stops the default button chrome/highlight from
    /// fighting with the glass material when there is.
    @ViewBuilder
    private var ringPodTappable: some View {
        if let onRingTap {
            Button(action: onRingTap) { ringPod }
                .buttonStyle(.plain)
        } else {
            ringPod
        }
    }

    private var ringPod: some View {
        podContent(drawsDiffuser: true)
            .frame(width: CGFloat(RingConfig.tabBarPodDiameter), height: CGFloat(RingConfig.tabBarPodDiameter))
            .opacity(playback?.opacity ?? 1)
    }

    // MARK: - Pod content
    //
    // `podContentStack` is used by BOTH the pod and the blurred duplicate
    // behind the glass. That duplicate is what gets refracted by the
    // material (see `ringPodStack`), so it has to be the same content —
    // leaving it hardcoded to `RingView` would make a photo pod lose the
    // refraction the ring pod has, which reads as the glass breaking
    // rather than as a content change.
    //
    // Three states, and the ring appears in exactly one of them: for
    // `.photo` and `.glyph` the ring goes away entirely and the pod is its
    // fill plus the content, optionally carrying a status capsule.

    /// The content's diameter for `.photo`/`.glyph`.
    ///
    /// The ring's own 34pt, not the pod's 62pt: without a ring the pod is
    /// a plain glass capsule, and content sized to its full width would
    /// touch the edges. Matching the ring's diameter also keeps the pod
    /// equally "full" whichever state it is in, so switching states is a
    /// comparison of content rather than of two different sizes.
    private var contentDiameter: CGFloat { CGFloat(RingConfig.tabBarRingDiameter) }

    /// The bubble is bigger than the ring: it is a sphere in a glass
    /// capsule, and at the ring's 34pt it read as a marble in a dish. 50pt
    /// leaves the capsule's own edge visible around it.
    private var bubbleDiameter: CGFloat { CGFloat(RingConfig.tabBarPodDiameter) * 0.8 }

    /// `drawsDiffuser` is `false` for the blurred backing copy behind the
    /// glass — see `RingView.drawsDiffuser`. Two stacked diffusers were
    /// what made the pod's ring look like different proportions from the
    /// large preview.
    @ViewBuilder
    private func podContent(drawsDiffuser: Bool) -> some View {
        switch config.podContent {
        case .ring:
            RingView(config: config,
                     diameter: CGFloat(RingConfig.tabBarRingDiameter),
                     overrideElapsed: playback?.elapsed,
                     drawsDiffuser: drawsDiffuser)
        case .photo, .glyph:
            // No badge here. The status is a tab bar *accessory* above the
            // bar — see `PodStatusAccessory` — not a mark on the pod.
            podInnerContent
                .frame(width: contentDiameter, height: contentDiameter)
        case .bubble:
            // One RealityKit scene per pod, not two: the blurred backing
            // copy (`drawsDiffuser: false`) is skipped. The bubble is its
            // own glass and does not need the material's refraction to
            // read as one.
            if drawsDiffuser {
                BubbleView(config: config, diameter: bubbleDiameter)
            } else {
                Color.clear.frame(width: bubbleDiameter, height: bubbleDiameter)
            }
        }
    }

    @ViewBuilder
    private var podInnerContent: some View {
        switch config.podContent {
        case .ring, .bubble:
            EmptyView()
        case .glyph:
            Image(systemName: config.podGlyph)
                .resizable()
                .scaledToFit()
                .fontWeight(.semibold)
                .padding(contentDiameter * 0.1)
                .foregroundStyle(iconColor(isSelected: true))
        case .photo:
            podPhoto
        }
    }

    /// The host's image once there is one; until then a placeholder that
    /// looks like a placeholder. A stock avatar here would make the design
    /// look finished while the actual question — does a photo belong in
    /// this slot at all — is still open.
    @ViewBuilder
    private var podPhoto: some View {
        if let podImage {
            podImage
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            ZStack {
                Circle().fill(.fill.tertiary)
                Circle().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .foregroundStyle(iconColor(isSelected: true).opacity(0.6))
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(contentDiameter * 0.26)
                    .foregroundStyle(iconColor(isSelected: true).opacity(0.7))
            }
        }
    }

    /// A single tab item: custom outline artwork when unselected, filled
    /// artwork when selected. Color is scheme-dependent — see
    /// `iconColor`/`textColor`. A real `Button`, so tapping actually
    /// switches the previewed tab content.
    ///
    /// Type is SF Pro Semibold 10pt (`.system` already resolves to SF Pro
    /// on both platforms), 12pt line height via `.lineSpacing`, 0 letter
    /// spacing via `.tracking(0)`, center-aligned. The selected item gets
    /// a fixed 76pt-wide pill behind it — 100% opacity, fully rounded
    /// (corner radius 100 clips to a capsule at this height), "Plus
    /// Darker" blend mode, filled with the system's `.fill.tertiary` —
    /// the standard adaptive fill meant to sit on top of vibrant/glass
    /// materials, which is what "Fills - Vibrant/Tertiary" is.
    private func tabItem(_ tab: DemoTab) -> some View {
        let isSelected = tab == selectedTab
        let appearance = config.appearance(for: tab)

        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                // Name and glyph come from the editable appearance, not
                // from the enum — see `TabAppearance`. `tab.rawValue` is
                // still the asset/identity key and must not be used as a
                // label, or renaming a tab would repoint its screenshot.
                appearance.glyph.image(selected: isSelected)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(iconColor(isSelected: isSelected))
                Text(appearance.name)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0)
                    .lineSpacing(2) // 12pt line height - 10pt font size
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(textColor(isSelected: isSelected))
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    Capsule()
                        .fill(.fill.tertiary)
                        .blendMode(.plusDarker)
                        .frame(width: 76)
                        .matchedGeometryEffect(id: "selectedTab", in: selectionNamespace)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
