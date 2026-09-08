#if os(macOS)
import AppKit

/// Copying animations between sections, via the system pasteboard.
///
/// The payload is the same JSON the Share menu writes, so a copied
/// animation can equally be pasted into a message or saved as a file —
/// and anything shared that way can be pasted back in. One format, not a
/// private clipboard that only works inside one window.
public enum AnimationPasteboard {

    /// Declared alongside the plain string so a paste from this app keeps
    /// its exact bytes, while a paste from anywhere else still works if
    /// the text happens to be an animation.
    private static let type = NSPasteboard.PasteboardType("com.nexusringapp.animations")

    public static func copy(_ presets: [RingPreset]) {
        guard !presets.isEmpty else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(presets) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: type)
        pasteboard.setString(String(decoding: data, as: UTF8.self), forType: .string)
    }

    /// Whatever animations are on the pasteboard, in order.
    ///
    /// Accepts a bare object as well as an array, matching what
    /// `RingPresetStore` accepts on import — a single animation shared by
    /// a teammate is one object, and refusing it here would be a
    /// distinction nobody asked for.
    public static func presets() -> [RingPreset] {
        let pasteboard = NSPasteboard.general
        let data = pasteboard.data(forType: type)
            ?? pasteboard.string(forType: .string).map { Data($0.utf8) }
        guard let data else { return [] }
        let decoder = JSONDecoder()
        if let many = try? decoder.decode([RingPreset].self, from: data) { return many }
        if let one = try? decoder.decode(RingPreset.self, from: data) { return [one] }
        return []
    }

    public static var hasAnimations: Bool {
        !presets().isEmpty
    }
}
#endif
