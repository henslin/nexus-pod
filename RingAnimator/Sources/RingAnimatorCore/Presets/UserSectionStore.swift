import Foundation

/// A section someone made themselves, alongside Nexus, Cue Library and Use
/// Cases in the sidebar.
///
/// It's shaped like Use Cases and not like the other two, because Use Cases
/// is the only one of the three it makes sense to have more of. Nexus is a
/// single live ring — its document is the ring itself, so a second one
/// would be a second app. The Cue Library is a fixed transcription of the
/// hardware spec, and a user-created copy of it would stop being a spec.
/// A named list of independently-tunable animations, each with its own
/// timeline, is the part that benefits from there being several.
public struct UserSection: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }

    /// Its presets live in their own file, keyed by id — the same
    /// arrangement Use Cases has with `use-cases.json`, so nothing can
    /// intermix and deleting a section can take its file with it.
    public var storeFileName: String { "section-\(id.uuidString).json" }
}

/// The list of user-created sections, and their order in the sidebar.
public final class UserSectionStore: ObservableObject {
    @Published public private(set) var sections: [UserSection] = []
    private let fileName: String

    public init(fileName: String = "user-sections.json") {
        self.fileName = fileName
        load()
    }

    @discardableResult
    public func add(named name: String) -> UserSection {
        // Appended, not inserted at the front: these are sidebar entries
        // sitting under three fixed ones, and a new section jumping above
        // an existing one would be a strange thing for a sidebar to do.
        // `RingPresetStore.add` inserts at the front for the opposite
        // reason — a fresh save should be the first thing you see.
        let section = UserSection(name: name.isEmpty ? "Untitled" : name)
        sections.append(section)
        save()
        return section
    }

    public func rename(_ id: UserSection.ID, to newName: String) {
        guard let index = sections.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        sections[index].name = trimmed.isEmpty ? sections[index].name : trimmed
        save()
    }

    /// Removes the section *and* the presets file behind it, plus every
    /// per-preset timeline in it. Nothing else would ever clean those up,
    /// and their names are keyed by ids that no longer exist anywhere.
    public func delete(_ id: UserSection.ID) {
        guard let section = sections.first(where: { $0.id == id }) else { return }
        let store = RingPresetStore(fileName: section.storeFileName)
        for preset in store.presets {
            TimelinePlayer.deleteStore(fileName: TimelinePlayer.useCaseFileName(preset.id))
        }
        if let url = Self.directory()?.appendingPathComponent(section.storeFileName) {
            try? FileManager.default.removeItem(at: url)
        }
        sections.removeAll { $0.id == id }
        save()
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        sections.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - Storage

    private static func directory() -> URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        let directory = base.appendingPathComponent("RingAnimator", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private var fileURL: URL? {
        Self.directory()?.appendingPathComponent(fileName)
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        sections = (try? JSONDecoder().decode([UserSection].self, from: data)) ?? []
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(sections) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
