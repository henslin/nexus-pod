import SwiftUI

/// The "listening"/"speaking" Liquid Glass pod shown just above the tab bar
/// while a hands-free ElevenLabs conversation is active — see
/// `RingConfig.voiceConversation`. Renders the back-and-forth as
/// Messages-app-style bubbles (your turns on the right, tinted with the
/// ring's own colors; the agent's on the left, neutral) instead of a single
/// line of text, and grows taller — each bubble up to 3 lines — to fit
/// longer replies instead of truncating everything to one line.
///
/// Public/shared (moved here from the Mac-only `RingAnimator` target, same
/// as `TabBarPreview`) so both the Mac design tool's phone mockup *and* the
/// real iOS app render the identical pill — one component, not two
/// hand-kept-in-sync copies. Mirrors `TabBarPreview`'s
/// `#available(iOS 26.0, macOS 26.0, *)` + pre-Glass fallback pattern —
/// both platforms need to be named explicitly, or the compiler falls back
/// to this package's declared iOS 17 minimum for whichever platform isn't
/// listed (see `TabBarPreview`'s doc comment for the full story on that).
public struct VoicePillView: View {
    @ObservedObject var controller: VoiceConversationController
    var width: CGFloat
    /// Tied to the ring's own colors (`RingConfig.primaryColor`/
    /// `secondaryColor`) so the pod — and the user's own bubbles — read as
    /// part of the same ring, rather than a generic system control.
    var primaryColor: Color
    var secondaryColor: Color

    public init(controller: VoiceConversationController, width: CGFloat, primaryColor: Color, secondaryColor: Color) {
        self.controller = controller
        self.width = width
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
    }

    /// Only the most recent turns are shown at once — enough to read the
    /// back-and-forth without the pod growing to fill the whole screen as
    /// a conversation goes on.
    private static let maxVisibleMessages = 3
    /// A capsule only reads well while the content is a single short line —
    /// once the pod can grow to multiple wrapped/multi-bubble lines, a
    /// fully-rounded end looks stretched rather than pill-shaped. A fixed
    /// continuous corner radius keeps it looking like a pill when short and
    /// a rounded card when tall.
    private static let cornerRadius: CGFloat = 22

    public var body: some View {
        pillBackground
            .frame(width: width)
            // Covers a *new* bubble appearing (either side) — slides up,
            // pod grows to fit it. Deliberately keyed on the *count*, not
            // the whole `messages` array: an existing bubble's text
            // changing doesn't retrigger this, since `.animation(value:)`
            // modifiers apply inconsistently across a view hierarchy this
            // deep (SwiftUI's own documented caveat) — that's what caused
            // the text to visibly outrun the bubble/pod's own resize
            // before. The agent's bubble *growing* as its reply streams in
            // is instead animated explicitly, at the actual `messages`
            // mutation in `VoiceConversationController` — `withAnimation`
            // at the source propagates reliably through this same
            // cross-container layout (including the pod's bottom-anchored
            // reposition against the tab bar below), which is what makes
            // it read as expanding upward rather than snapping per word.
            .animation(.bouncy(duration: 0.32, extraBounce: 0.05), value: controller.messages.count)
    }

    @ViewBuilder
    private var pillBackground: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusRow

            ForEach(visibleMessages) { message in
                bubble(for: message)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            // Active (animated, full-opacity) for both listening *and*
            // speaking, so the waveform keeps reacting to the agent's voice
            // even between bubble updates.
            WaveformBars(level: controller.level, isActive: true, primaryColor: primaryColor, secondaryColor: secondaryColor)
                .frame(width: 30, height: 20)

            Text(statusText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
    }

    private var statusText: String {
        switch controller.mode {
        case .listening:
            return controller.messages.isEmpty ? "Listening…" : "Listening"
        case .speaking:
            return "Responding…"
        }
    }

    private var visibleMessages: [VoiceMessage] {
        Array(controller.messages.suffix(Self.maxVisibleMessages))
    }

    @ViewBuilder
    private func bubble(for message: VoiceMessage) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.role == .user {
                Spacer(minLength: 32)
            } else {
                // A small "avatar" dot on the agent's bubbles only — same
                // convention Messages uses (the other person gets one, "you"
                // don't) — so which side is talking reads at a glance
                // instead of depending on remembering left-vs-right.
                agentAvatar
            }

            Text(message.text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(3)
                .truncationMode(.tail)
                .foregroundStyle(message.role == .user ? .white : .primary)
                // SwiftUI's default `Text` content transition crossfades
                // between old and new copy whenever it changes inside an
                // animated transaction — which every streamed-in word was
                // doing, since `.animation(value: controller.messages)`
                // above wraps every delta update along with real structural
                // changes. `.identity` makes text updates snap in place
                // instantly (how a real chat app's streaming text behaves)
                // while the bubble/pod around it still resizes smoothly.
                .contentTransition(.identity)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubbleBackground(for: message.role), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if message.role == .agent { Spacer(minLength: 32) }
        }
        // New bubbles rise up into place from below rather than just
        // popping in — same idea as a Messages-app bubble arriving. Older
        // ones dropping off the top (`visibleMessages`' suffix window) just
        // fade rather than sliding, so it doesn't look like they're falling
        // out the bottom.
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }

    private var agentAvatar: some View {
        Circle()
            .fill(LinearGradient(colors: [primaryColor, secondaryColor], startPoint: .top, endPoint: .bottom))
            .frame(width: 16, height: 16)
    }

    /// Your bubbles pick up the ring's own primary→secondary gradient — the
    /// same "cool tie-in" idea as the waveform's coloring. The agent's
    /// bubbles use a stronger adaptive fill than before (`.fill.secondary`
    /// rather than a faint 8%-opacity tint) — against the glass pod's own
    /// translucency, the faint version barely read as a bubble at all,
    /// which was a big part of "who said what" being unclear. Both branches
    /// are erased to `AnyShapeStyle` so this can return one type despite
    /// `LinearGradient` and `.fill.secondary` being unrelated `ShapeStyle`s.
    private func bubbleBackground(for role: VoiceMessage.Role) -> AnyShapeStyle {
        if role == .user {
            AnyShapeStyle(LinearGradient(colors: [primaryColor, secondaryColor], startPoint: .leading, endPoint: .trailing))
        } else {
            AnyShapeStyle(.fill.secondary)
        }
    }
}

/// A small animated bar waveform — bar heights driven by `level` (0...1)
/// plus per-bar phase offsets so they don't all move in lockstep like a
/// single VU meter. Idles as short flat bars when `isActive` is false
/// (used while waiting rather than actually listening).
private struct WaveformBars: View {
    var level: Double
    var isActive: Bool
    var primaryColor: Color
    var secondaryColor: Color

    private let barCount = 5

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            // `.foregroundStyle(gradient)` on the HStack would re-render the
            // full gradient inside *each* bar individually (SwiftUI scales
            // a style to whatever shape it's directly applied to) — barely
            // visible on a 3pt-wide capsule. Masking one gradient that
            // spans the whole group's width with the bar shapes instead
            // makes it a single sweep across all 5 bars: bar 1 reads as
            // primary, bar 5 as secondary, same as the ring itself.
            LinearGradient(colors: [primaryColor, secondaryColor], startPoint: .leading, endPoint: .trailing)
                .mask(
                    HStack(alignment: .center, spacing: 3) {
                        ForEach(0..<barCount, id: \.self) { i in
                            Capsule()
                                .frame(width: 3, height: barHeight(index: i, time: t))
                        }
                    }
                    .frame(height: 20)
                )
                .frame(height: 20)
                .opacity(isActive ? 0.85 : 0.3)
        }
    }

    private func barHeight(index: Int, time: Double) -> CGFloat {
        guard isActive else { return 3 }
        let seed = Double(index) * 1.7
        // Faster, more spread-out per-bar phases so bars visibly move
        // independently instead of bobbing together in a slow lump.
        let jitter = (sin(time * (6 + seed * 1.6) + seed) + 1) / 2
        // Square-root response: mic RMS rarely gets close to 1.0 during
        // normal speech, so a linear mapping barely animates. Boosting the
        // low end keeps the bars visibly alive at normal talking volume,
        // not just on loud peaks.
        let boosted = pow(min(max(level, 0), 1), 0.5)
        let amplitude = 0.25 + 0.75 * jitter
        // `boosted * amplitude` goes to exactly 0 whenever `level` does —
        // deliberately: bars should sit flat at the `max(3, ...)` floor
        // during real silence (including ElevenLabs' natural pauses
        // between sentences) rather than keep moving on their own. An
        // earlier version added a small always-on sway here so the bars
        // never looked "frozen" — but that meant they visibly moved even
        // with no mic signal at all, reading as fake/disconnected from
        // your actual voice. Flat-when-silent, alive-when-spoken-into is
        // the correct behavior for something claiming to show live input.
        return max(3, 3 + 20 * CGFloat(boosted * amplitude))
    }
}

/// Scales/offsets the voice pill so it visibly grows out of the ring pod's
/// exact center, then settles into its normal laid-out position above the
/// tab bar — without the coordinate-space issues `matchedGeometryEffect`
/// runs into crossing in and out of `TabBarPreview`'s `GlassEffectContainer`
/// (that version ended up just fading in behind the tab bar instead of
/// animating from the ring).
///
/// The math is fixed constants, not a guess: the pill and the tab bar +
/// ring row below it are both exactly the same width (see the call sites in
/// `PhoneMockupView.screen` and `RootView`), so the ring pod's horizontal
/// center as a fraction of that shared width — `(width - 62/2) / width` —
/// is the same fraction whether measured against the pill's own bounds or
/// the row's. For a `VStack(spacing: 10)` with the pill on top and the
/// 62pt-tall tab bar/ring row below, the vertical distance from the pill's
/// *bottom edge* down to the ring's center is always exactly
/// `10 (spacing) + 62/2 (half the row's height) = 41`pt, regardless of the
/// pill's own height — so anchoring the shrink point at the pill's bottom
/// edge and offsetting by that fixed 41pt lands it precisely on the ring
/// every time.
struct GrowFromRingModifier: ViewModifier {
    var isSource: Bool
    /// The pill's own width — same as the tab bar + ring row's width at
    /// the call site, so this doubles as the row width for the fraction
    /// math below. Passed in rather than hardcoded so this stays correct
    /// if the row's width ever changes.
    var rowWidth: CGFloat

    private static let ringPodWidth: CGFloat = 62
    private static let ringCenterYOffset: CGFloat = 41 // spacing (10) + half the row height (31)

    func body(content: Content) -> some View {
        let ringCenterXFraction = 1 - (Self.ringPodWidth / 2 / rowWidth)
        content
            .scaleEffect(isSource ? 0.02 : 1, anchor: UnitPoint(x: ringCenterXFraction, y: 1))
            .offset(y: isSource ? Self.ringCenterYOffset : 0)
            .opacity(isSource ? 0 : 1)
    }
}

extension AnyTransition {
    /// Used by both `PhoneMockupView` (Mac) and `RootView` (iOS) for the
    /// voice pill's entrance/exit — see `GrowFromRingModifier`'s doc
    /// comment for the geometry reasoning.
    public static func growFromRing(rowWidth: CGFloat) -> AnyTransition {
        .modifier(
            active: GrowFromRingModifier(isSource: true, rowWidth: rowWidth),
            identity: GrowFromRingModifier(isSource: false, rowWidth: rowWidth)
        )
    }
}
