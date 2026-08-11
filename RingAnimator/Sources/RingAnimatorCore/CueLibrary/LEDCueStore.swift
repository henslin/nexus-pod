import Foundation

/// Holds whatever the team has tweaked away from `LEDCueLibrary`'s defaults,
/// persisted as JSON in Application Support. Cues that haven't been touched
/// simply aren't in `overrides` — the default lives in the library itself,
/// so resetting a cue is just deleting its entry here.
public final class LEDCueStore: ObservableObject {
    @Published public private(set) var overrides: [String: LEDCueParameters] = [:]

    public init() {
        load()
    }

    /// The effective parameters for a cue: the saved override if there is
    /// one, otherwise the shipped default.
    public func parameters(for cue: LEDCue) -> LEDCueParameters {
        overrides[cue.id] ?? cue.defaultParameters
    }

    public func isModified(_ cue: LEDCue) -> Bool {
        overrides[cue.id] != nil
    }

    /// Saves new parameters for a cue. If they exactly match the default
    /// again, the override is dropped instead of stored, so "tweak back to
    /// the default by hand" behaves the same as pressing Reset.
    public func update(_ params: LEDCueParameters, for cue: LEDCue) {
        if params == cue.defaultParameters {
            overrides.removeValue(forKey: cue.id)
        } else {
            overrides[cue.id] = params
        }
        save()
    }

    public func reset(_ cue: LEDCue) {
        guard overrides[cue.id] != nil else { return }
        overrides.removeValue(forKey: cue.id)
        save()
    }

    public func resetAll() {
        guard !overrides.isEmpty else { return }
        overrides.removeAll()
        save()
    }

    /// The full library with every override applied — what you'd hand to
    /// an engineer as the source of truth for on-device behavior.
    public func exportSnapshot() -> [LEDCue] {
        LEDCueLibrary.all.map { cue in
            var resolved = cue
            resolved.defaultParameters = parameters(for: cue)
            return resolved
        }
    }

    public func exportSnapshotJSON() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(exportSnapshot())) ?? Data()
    }

    // MARK: - Persistence

    private static var storageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("RingAnimator", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cue-overrides.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.storageURL) else { return }
        overrides = (try? JSONDecoder().decode([String: LEDCueParameters].self, from: data)) ?? [:]
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(overrides) else { return }
        try? data.write(to: Self.storageURL, options: .atomic)
    }
}
