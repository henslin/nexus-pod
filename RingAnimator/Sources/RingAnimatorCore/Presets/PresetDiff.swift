import Foundation

/// What changed between two versions of an animation, and how to put those
/// same changes onto a different one.
///
/// Per-section "Apply to All" buttons were the first idea and don't
/// survive contact: turn on Smooth and then Particles and you have two
/// buttons to remember to press, and nothing tells you that you missed one.
/// One control that applies *whatever you changed* has no such state to
/// keep track of.
///
/// Which means the unit is a **field**, not a section — and enumerating
/// eighty-odd fields by hand is exactly the kind of list that goes stale
/// the next time someone adds a knob (see `ControlsSectionReset`, which has
/// that problem and says so). `RingPreset` is already `Codable`, so this
/// diffs the encoded form instead: whatever the encoder knows about, this
/// knows about, including fields added after it was written.
public struct PresetDiff {
    /// Encoded keys whose values differ, and the values to write.
    private let changes: [String: Any]

    public var changedKeyCount: Int { changes.count }
    public var isEmpty: Bool { changes.isEmpty }

    /// Fields that identify *which* animation this is rather than what it
    /// looks like. Applying a name to sixty-nine animations would give you
    /// sixty-nine animations with one name.
    private static let identityKeys: Set<String> = ["id", "name", "createdAt"]

    public init?(from baseline: RingPreset, to edited: RingPreset) {
        guard
            let before = Self.dictionary(baseline),
            let after = Self.dictionary(edited)
        else { return nil }

        var changed: [String: Any] = [:]
        for (key, value) in after where !Self.identityKeys.contains(key) {
            let old = before[key]
            // Both sides come out of `JSONSerialization`, so every value is
            // an `NSObject` subclass and `isEqual` is the right comparison —
            // `==` on `Any` would not compile and casting each type by hand
            // would be the field list this exists to avoid.
            if let old = old as? NSObject, let new = value as? NSObject {
                if !old.isEqual(new) { changed[key] = value }
            } else if old == nil {
                changed[key] = value
            }
        }
        // A field present before and absent after — a value that went nil.
        for key in before.keys where after[key] == nil && !Self.identityKeys.contains(key) {
            changed[key] = NSNull()
        }
        self.changes = changed
    }

    /// Applies the same changes to another animation, keeping its identity.
    public func applied(to preset: RingPreset) -> RingPreset? {
        guard !changes.isEmpty, var dictionary = Self.dictionary(preset) else { return nil }
        for (key, value) in changes {
            if value is NSNull {
                dictionary.removeValue(forKey: key)
            } else {
                dictionary[key] = value
            }
        }
        guard
            let data = try? JSONSerialization.data(withJSONObject: dictionary),
            let updated = try? JSONDecoder().decode(RingPreset.self, from: data)
        else { return nil }
        return updated
    }

    private static func dictionary(_ preset: RingPreset) -> [String: Any]? {
        guard
            let data = try? JSONEncoder().encode(preset),
            let object = try? JSONSerialization.jsonObject(with: data)
        else { return nil }
        return object as? [String: Any]
    }
}
