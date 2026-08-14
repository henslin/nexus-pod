import Foundation

/// Persists a collection of bookmarked `RingConfig` snapshots. Originally
/// just the "Saved Animations" column in Nexus (see `SavedPresetsView`),
/// now also reused as-is for the "Use Cases" section (see
/// `UseCaseListView`/`UseCaseDetailView`) — same shape of data (a named,
/// fully-tunable `RingPreset`), just a second independent collection with
/// its own JSON file, so the two lists never intermix. `fileName`
/// distinguishes the two on disk.
///
/// Modeled directly on `LEDCueStore`: same Application Support JSON file
/// convention, same plain load/save-on-mutation approach. Kept here in
/// `RingAnimatorCore` (like `LEDCueStore`) even though today's UI for it is
/// Mac-only, so it's ready to reuse from the iOS app's Nexus if that
/// ever gets a matching feature.
public final class RingPresetStore: ObservableObject {
    @Published public private(set) var presets: [RingPreset] = []
    private let fileName: String

    public init(fileName: String = "saved-presets.json") {
        self.fileName = fileName
        load()
    }

    /// Newest first, so a freshly-saved animation shows up at the top of the
    /// scrolling column without having to scroll to find it.
    @discardableResult
    public func add(_ preset: RingPreset) -> RingPreset {
        presets.insert(preset, at: 0)
        save()
        return preset
    }

    public func rename(_ id: RingPreset.ID, to newName: String) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        presets[index].name = trimmed
        save()
    }

    public func delete(_ id: RingPreset.ID) {
        presets.removeAll { $0.id == id }
        save()
    }

    /// Overwrites an existing preset's full field set in place — used by
    /// `UseCaseDetailView` for continuous autosave while editing, as
    /// opposed to `rename(_:to:)` (name only) or `add(_:)` (a brand new
    /// entry). A no-op if `preset.id` isn't already in the list, so a
    /// stray call after a preset's been deleted elsewhere can't
    /// resurrect it.
    public func update(_ preset: RingPreset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[index] = preset
        save()
    }

    // MARK: - Export
    //
    // The app has no macOS share sheet or file-import UI anywhere yet — the
    // established convention (see `ExportView`, `CueListView`) is a plain
    // `NSSavePanel`/`NSOpenPanel` and handing the resulting file to a
    // teammate over Slack/AirDrop/email. These two just hand back `Data`;
    // `SavedPresetsView` owns the actual panels.

    public func exportPresetJSON(_ preset: RingPreset) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(preset)) ?? Data()
    }

    /// Every saved animation, as one file — for handing off your whole
    /// collection at once instead of one at a time.
    public func exportLibraryJSON() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(presets)) ?? Data()
    }

    // MARK: - Import

    public enum ImportError: Error {
        case unrecognizedFormat
    }

    /// Accepts either a single exported preset's JSON or a whole exported
    /// library's JSON (an array) — whichever a teammate hands you — and
    /// adds every preset found to the list. An existing preset with the
    /// same `id` is replaced in place (re-importing your own export updates
    /// it rather than duplicating it); anything new is added to the top.
    @discardableResult
    public func importJSON(_ data: Data) -> Result<Int, ImportError> {
        let decoder = JSONDecoder()
        let imported: [RingPreset]
        if let library = try? decoder.decode([RingPreset].self, from: data), !library.isEmpty {
            imported = library
        } else if let single = try? decoder.decode(RingPreset.self, from: data) {
            imported = [single]
        } else {
            return .failure(.unrecognizedFormat)
        }

        for preset in imported {
            if let index = presets.firstIndex(where: { $0.id == preset.id }) {
                presets[index] = preset
            } else {
                presets.insert(preset, at: 0)
            }
        }
        save()
        return .success(imported.count)
    }

    // MARK: - Persistence

    private var storageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("RingAnimator", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        presets = (try? JSONDecoder().decode([RingPreset].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(presets) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
