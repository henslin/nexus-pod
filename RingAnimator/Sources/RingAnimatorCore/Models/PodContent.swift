import SwiftUI

/// What the tab bar's pod shows.
///
/// The pod has only ever drawn `RingView`, because the ring was the whole
/// subject. But the pod is a fixed 62pt slot in a host app's tab bar, and
/// what belongs in that slot is a product question the ring doesn't answer
/// by itself.
///
/// **Three states, not four.** An earlier pass had `status` as its own
/// case and a toggle for drawing the ring *around* photo/glyph content.
/// Both are gone (Chris, 2026-09-10): the ring does not frame content —
/// for photo and glyph it goes away entirely and the pod falls back to its
/// fill (`PodFill`) — and status is not something the pod shows at all.
///
/// **Status is a tab bar accessory, not a badge.** It is the Apple Music
/// pattern: the pod becomes a photo or a glyph, and a glass panel the full
/// width of the bar spawns from the pod and says what happened, in a
/// sentence — "John arrived home." See `PodStatusAccessory`. A second
/// earlier pass drew it as a small capsule on the pod, which could carry
/// two characters and was the wrong idea rather than the wrong size.
///
/// Why the framing idea died is worth keeping: at the pod's geometry the
/// ring is 34pt with a ~22pt hole, so framed content was an illegible
/// smudge. Growing the ring to the pod's full 62pt fixed the legibility but
/// meant the ring changed size depending on what was inside it, which is
/// the wrong trade for a mark that is the product's identity.
///
/// **This is an exploration surface, not an API yet.** The host app will
/// eventually supply this content at runtime; the seam is `TabBarPreview`'s
/// `podImage`, which is `nil` here and drawn as an obvious placeholder.
public enum PodContent: String, CaseIterable, Identifiable, Codable, Sendable {
    /// The animated ring, in any of its animation types — the original
    /// behaviour, unchanged, and the only state the ring appears in.
    case ring
    /// An image the host app supplies, typically the signed-in user.
    case photo
    /// An SF Symbol, the way an assistant affordance usually reads.
    case glyph

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .ring:  return "Ring"
        case .photo: return "Photo"
        case .glyph: return "Glyph"
        }
    }

    /// Whether this state can carry a status accessory and a pod fill. The
    /// ring is its own thing and takes neither — it is the quiet default
    /// the other two interrupt.
    public var takesStatusAndFill: Bool { self != .ring }

    public var summary: String {
        switch self {
        case .ring:
            return "The animated ring, in whichever animation type is set. No message and no fill — this is the quiet default state."
        case .photo:
            return "An image the host app supplies — a person who just arrived, typically — with an optional message above the bar. The ring goes away. Placeholder until a host image is passed in."
        case .glyph:
            return "An SF Symbol, with an optional message above the bar. The ring goes away."
        }
    }
}

/// What sits behind photo/glyph content once the ring is gone.
///
/// The pod is a Liquid Glass capsule either way; this is whether that glass
/// carries a tint of its own. `.standard` leaves it as the bar's glass, so
/// the pod reads as part of the bar. `.tinted` gives it a colour tied to
/// what it is showing — an alert glyph on red, "Live" on green — so the pod
/// can carry state at a glance without the ring's animation.
public enum PodFill: String, CaseIterable, Identifiable, Codable, Sendable {
    case standard
    case tinted

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .standard: return "Default"
        case .tinted:   return "Tinted Glass"
        }
    }

    public var summary: String {
        switch self {
        case .standard:
            return "The same glass as the tab bar, so the pod reads as part of it."
        case .tinted:
            return "Glass carrying a colour tied to the glyph or status, so the pod can show state without animating."
        }
    }
}

/// How the status accessory enters and leaves.
///
/// `.growFromPod` is the established one — the voice pill already uses it,
/// and it is the motion that says *this came from the pod* rather than
/// *a banner appeared*. The other two exist because that claim is worth
/// testing against the alternatives rather than assuming.
public enum PodStatusEntrance: String, CaseIterable, Identifiable, Codable, Sendable {
    case growFromPod
    case slideUp
    case fade

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .growFromPod: return "Grow From Pod"
        case .slideUp:     return "Slide Up"
        case .fade:        return "Fade"
        }
    }

    public var summary: String {
        switch self {
        case .growFromPod:
            return "Expands out of the pod itself, the way the voice pill does. Says the message came from the Nexus tab."
        case .slideUp:
            return "Rises from behind the tab bar. Reads as a notification arriving rather than as the pod speaking."
        case .fade:
            return "Appears in place. The quietest option, and the one that says least about where it came from."
        }
    }
}
