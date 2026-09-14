import SwiftUI

/// The glass shell both bottom accessories share.
///
/// `VoicePillView` and `PodStatusAccessory` are the same object as far as
/// the eye is concerned — a Liquid Glass panel the width of the tab bar
/// row, resting just above it, spawned from the pod. Only their *content*
/// differs (a conversation's bubbles vs one message), so only the content
/// is written twice. Extracted the moment there was a second one, rather
/// than after the two had drifted: this codebase already pays for
/// `TabBarPreview` and `VoicePillView` being shared rather than copied.
///
/// The corner radius lives here for the same reason. A capsule reads well
/// only while the content is one short line; once the panel can grow to
/// several wrapped lines a fully-rounded end looks stretched, so a fixed
/// continuous radius keeps it a pill when short and a card when tall.
public struct BottomAccessoryPill<Content: View>: View {
    public static var cornerRadius: CGFloat { 22 }

    var width: CGFloat
    @ViewBuilder var content: Content

    public init(width: CGFloat, @ViewBuilder content: () -> Content) {
        self.width = width
        self.content = content()
    }

    public var body: some View {
        // Mirrors `TabBarPreview`'s availability pattern — both platforms
        // named explicitly, or the compiler falls back to the package's
        // declared iOS 17 minimum for whichever isn't listed.
        if #available(iOS 26.0, macOS 26.0, *) {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                .frame(width: width)
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                .frame(width: width)
        }
    }
}

/// The pod's status message, rendered as a **tab bar accessory** — the
/// Apple Music pattern: a glass panel the full width of the tab bar row,
/// resting above it, spawned from the pod itself.
///
/// **This is not a badge.** An earlier pass drew the status as a small
/// capsule sitting on the pod's own content, which is a different idea
/// entirely and could only ever carry two or three characters. The point
/// (Chris, 2026-09-10) is that the pod changes to a photo or a glyph *and*
/// a panel says why, in a sentence: the ring is animating quietly, a known
/// person arrives home, the pod becomes their photo and the panel spawns
/// saying "John arrived home." So it has to hold a small paragraph, which
/// a badge cannot.
///
/// Wrapping, not truncation, is the whole requirement — `lineLimit` is
/// deliberately absent. `BottomAccessoryPill` grows to fit, exactly as the
/// voice pill grows for a long reply.
public struct PodStatusAccessory: View {
    var width: CGFloat
    var message: String
    /// Matches the pod's own tint so the panel and the pod read as one
    /// event rather than two things that happened to appear together.
    var tint: Color
    /// The pod's content, echoed as a small leading mark so the panel says
    /// *who/what* as well as *what happened* — the same job
    /// `VoicePillView`'s waveform does in its status row.
    var content: PodContent
    var glyph: String
    /// Supplied only when the accessory is dismissible — `nil` leaves it
    /// inert, so "can be tapped away" is expressed by whether there is
    /// anything to tap rather than by a flag the view has to remember to
    /// check.
    var onDismiss: (() -> Void)?

    public init(width: CGFloat, message: String, tint: Color, content: PodContent, glyph: String, onDismiss: (() -> Void)? = nil) {
        self.width = width
        self.message = message
        self.tint = tint
        self.content = content
        self.glyph = glyph
        self.onDismiss = onDismiss
    }

    public var body: some View {
        BottomAccessoryPill(width: width) {
            HStack(alignment: .top, spacing: 10) {
                mark
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            // Before the shell's own sizing, not after — a gesture applied
            // outside padding takes the padded frame as its hit area, which
            // is the modifier-order bug that made a whole tab bar
            // untappable on the sibling project.
            .contentShape(Rectangle())
            .onTapGesture { onDismiss?() }
        }
    }

    /// A 20pt echo of what the pod is showing. For `.photo` this is the
    /// same placeholder the pod draws, deliberately — a host image is not
    /// wired up yet, and inventing a different stand-in here would make
    /// the two look like different people.
    @ViewBuilder
    private var mark: some View {
        Group {
            switch content {
            case .glyph, .bubble:
                // The bubble's mark is its glyph — a 20pt RealityKit
                // scene in a status pill would be a second GPU scene for
                // an echo nobody looks at.
                Image(systemName: glyph)
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.semibold)
                    .padding(3)
                    .foregroundStyle(tint)
            case .photo:
                ZStack {
                    Circle().fill(.fill.tertiary)
                    Image(systemName: "person.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(5)
                        .foregroundStyle(.secondary)
                }
            case .ring:
                Circle().fill(tint)
            }
        }
        .frame(width: 20, height: 20)
    }
}
