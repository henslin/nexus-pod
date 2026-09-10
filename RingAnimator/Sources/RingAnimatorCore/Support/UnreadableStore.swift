import Foundation

/// What to do with a file that exists but won't decode.
///
/// Every store in this app followed the same shape:
///
/// ```swift
/// guard let data = try? Data(contentsOf: url) else { return }
/// items = (try? JSONDecoder().decode([Item].self, from: data)) ?? []
/// ```
///
/// which reads "if the file is unreadable, start empty" — and the very
/// next edit calls `save()`, which writes `[]` over it. A single truncated
/// write, a half-synced iCloud file or a schema change silently destroys
/// the library, and the first anyone knows is an empty list with no way
/// back.
///
/// It costs nothing to be careful here. Before the empty state is allowed
/// to stand, the unreadable file is moved aside under a timestamped name.
/// The app still opens empty — there is genuinely nothing to show — but
/// the bytes survive, and "my animations are gone" has an answer that
/// isn't "they are".
public enum UnreadableStore {
    /// Renames `url` out of the way, returning where it went.
    ///
    /// A move rather than a copy: leaving the original in place would let
    /// the next `save()` overwrite it, which is the whole thing being
    /// avoided.
    @discardableResult
    public static func setAside(_ url: URL) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }

        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        let suffix = stamp.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let destination = url
            .deletingPathExtension()
            .appendingPathExtension("unreadable-\(suffix)")
            .appendingPathExtension(url.pathExtension)

        do {
            try fm.moveItem(at: url, to: destination)
            return destination
        } catch {
            // Couldn't move it — then leave it exactly where it is rather
            // than pressing on. The caller's `save()` may still overwrite
            // it, but a failed rescue is no reason to also delete the
            // evidence.
            return nil
        }
    }
}
