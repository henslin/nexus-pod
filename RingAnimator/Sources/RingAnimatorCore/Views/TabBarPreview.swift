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

    public init(config: RingConfig, selectedTab: Binding<DemoTab>, width: CGFloat = 340, onRingTap: (() -> Void)? = nil) {
        self.config = config
        self._selectedTab = selectedTab
        self.width = width
        self.onRingTap = onRingTap
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
        RingView(config: config, diameter: 34)
            .frame(width: 62, height: 62)
            .blur(radius: 4)
            .opacity(0.8)
    }

    @ViewBuilder
    private var ringPodGlass: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            ringPodTappable.glassEffect(config.glass, in: Capsule())
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
        RingView(config: config, diameter: 34)
            .frame(width: 62, height: 62)
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

        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                (isSelected ? tab.filledImage : tab.outlineImage)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(iconColor(isSelected: isSelected))
                Text(tab.rawValue)
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
