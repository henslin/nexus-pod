import Foundation
import CryptoKit

/// The animations that ship *inside* the app, and the machinery for
/// reconciling them with whatever's on this machine when a new build
/// arrives.
///
/// The problem this solves: the use cases used to live only in Application
/// Support, put there by importing a folder of Blender scripts. Anyone
/// given a copy of the app got an empty column. Bundling them makes the
/// library part of the build — but then the build and the person both have
/// opinions about the same animation, and an update has to decide whose
/// wins without quietly throwing anyone's work away.
public enum UseCaseLibrary {

    /// What ships in the app.
    public struct Bundle: Decodable, Sendable {
        /// When this library was cut. Shown at the top of the column so
        /// "are these current?" has an answer that isn't the app version.
        public let generatedAt: Date
        public let presets: [RingPreset]

        private enum CodingKeys: String, CodingKey {
            case generatedAt, presets
        }

        /// The timestamp is parsed by hand rather than by setting the
        /// decoder's date strategy to `.iso8601`, because that strategy
        /// would apply to `RingPreset.createdAt` too — which `JSONEncoder`
        /// wrote as a number. Setting it made the whole library fail to
        /// decode, which looks exactly like the resource being missing.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let stamp = try container.decode(String.self, forKey: .generatedAt)
            generatedAt = ISO8601DateFormatter().date(from: stamp) ?? .distantPast
            presets = try container.decode([RingPreset].self, forKey: .presets)
        }
    }

    /// What each bundled animation looked like when it was installed here.
    ///
    /// This is what makes an update able to tell "you changed this" from
    /// "you never touched it", without asking. An animation whose current
    /// fingerprint still matches the one recorded at install is untouched,
    /// so a newer version from the app can replace it. One that differs is
    /// yours, and the update leaves it alone.
    public struct InstallRecord: Codable, Sendable {
        public var libraryGeneratedAt: Date?
        /// Preset id → fingerprint of the bundled copy that was installed.
        public var fingerprints: [String: String] = [:]
    }

    // MARK: - The bundled library

    public static let bundled: Bundle? = {
        guard let url = Foundation.Bundle.module.url(forResource: "use-case-library", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Bundle.self, from: data)
    }()

    // MARK: - Reconciling

    /// What a sync did, for telling someone about it afterwards.
    public struct Outcome: Equatable, Sendable {
        public var added: [String] = []
        public var updated: [String] = []
        /// Bundled animations left alone because they've been edited here.
        public var keptYours: [String] = []

        public var isEmpty: Bool {
            added.isEmpty && updated.isEmpty && keptYours.isEmpty
        }

        /// Whether anything actually moved.
        ///
        /// `keptYours` is not a change — it's the same answer every launch
        /// for as long as an animation stays edited, so telling someone
        /// about it on its own would be a notification that never stops.
        /// It's worth saying only alongside something that did change.
        public var changedAnything: Bool {
            !added.isEmpty || !updated.isEmpty
        }

        public var summary: String {
            var parts: [String] = []
            if !added.isEmpty { parts.append("\(added.count) added") }
            if !updated.isEmpty { parts.append("\(updated.count) updated") }
            if !keptYours.isEmpty { parts.append("\(keptYours.count) of yours kept") }
            return parts.joined(separator: ", ")
        }
    }

    /// Brings `store` in line with the bundled library.
    ///
    /// The rules, and the reasoning for each:
    ///
    /// - **Not here, never installed** → add it. A new animation in a new
    ///   build should show up.
    /// - **Here, unchanged since it was installed** → replace it. You never
    ///   touched it, so this is just an update.
    /// - **Here, and you've changed it** → keep yours, untouched, and say
    ///   so afterwards. Losing someone's work to an app update is the one
    ///   outcome worth ruling out completely.
    /// - **Installed once, gone now** → leave it gone. You deleted it, and
    ///   an update that resurrects deleted animations is an update people
    ///   learn to dread.
    /// - **Yours alone, never in a bundle** → untouched, always.
    @discardableResult
    public static func sync(into store: RingPresetStore) -> Outcome {
        guard let bundled else { return Outcome() }
        var record = loadRecord()
        var outcome = Outcome()

        var updates: [RingPreset] = []
        var additions: [RingPreset] = []

        for preset in bundled.presets {
            let key = preset.id.uuidString
            let bundledFingerprint = fingerprint(preset)

            guard let existing = store.presets.first(where: { $0.id == preset.id }) else {
                if record.fingerprints[key] == nil {
                    additions.append(preset)
                    record.fingerprints[key] = bundledFingerprint
                    outcome.added.append(preset.name)
                }
                // Otherwise: installed once, deleted since. Stays deleted.
                continue
            }

            let installed = record.fingerprints[key]
            if installed == nil {
                // Present here but never recorded — the library it came from
                // predates this record (or it was imported by hand). Treat
                // it as yours: adopting it silently would be a guess, and
                // the guess that overwrites is the expensive one.
                record.fingerprints[key] = fingerprint(existing)
                continue
            }

            if fingerprint(existing) == installed {
                if bundledFingerprint != installed {
                    updates.append(preset)
                    record.fingerprints[key] = bundledFingerprint
                    outcome.updated.append(preset.name)
                }
            } else {
                outcome.keptYours.append(existing.name)
            }
        }

        for preset in updates { store.update(preset) }
        if !additions.isEmpty { store.append(contentsOf: additions) }

        record.libraryGeneratedAt = bundled.generatedAt
        save(record)
        return outcome
    }

    // MARK: - Where an animation came from

    /// What to show next to an animation's name.
    public enum Origin: Equatable, Sendable {
        /// Shipped with the app and untouched since.
        case bundled
        /// Shipped with the app, changed here.
        case edited
        /// Made here, or imported by hand. Never in a bundle.
        case local

        public var badge: String? {
            switch self {
            case .bundled: return nil
            case .edited: return "Edited"
            case .local: return "Local"
            }
        }
    }

    /// Deliberately derived rather than stored on `RingPreset`: origin is a
    /// fact about *this machine's* history with an animation, not about the
    /// animation, so writing it into the file would send it to whoever you
    /// shared it with, where it would be wrong.
    ///
    /// It also keeps the name clean. A "Custom" or "Local" suffix in the
    /// title would follow the animation into exported filenames and shared
    /// files, and there's no undoing that once it's out.
    public static func origin(of preset: RingPreset, record: InstallRecord? = nil) -> Origin {
        let record = record ?? loadRecord()
        guard let installed = record.fingerprints[preset.id.uuidString] else { return .local }
        return fingerprint(preset) == installed ? .bundled : .edited
    }

    public static func currentRecord() -> InstallRecord { loadRecord() }

    // MARK: - Fingerprints and storage

    /// A hash of everything about the animation, name included — renaming
    /// one is editing it.
    public static func fingerprint(_ preset: RingPreset) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(preset) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static var recordURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("RingAnimator", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("use-case-install-record.json")
    }

    /// The record is read by `origin(of:)`, which every row in the Use
    /// Cases column calls on every redraw — 69 rows, each animating a
    /// thumbnail. Reading a file that often is not a thing to find out
    /// about later, so the record is held in memory and only re-read when
    /// something writes it.
    ///
    /// `nonisolated(unsafe)` with an explicit lock rather than an actor:
    /// `origin(of:)` is called from `View.body`, which can't await.
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cachedRecord: InstallRecord?

    /// Drops the cached record. Only needed by something that writes the
    /// file behind `save(_:)`'s back — which in practice means `SyncCheck`,
    /// forging the state a new build's library would produce.
    public static func invalidateCache() {
        cacheLock.lock()
        cachedRecord = nil
        cacheLock.unlock()
    }

    private static func loadRecord() -> InstallRecord {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cachedRecord { return cachedRecord }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = (try? Data(contentsOf: recordURL))
            .flatMap { try? decoder.decode(InstallRecord.self, from: $0) } ?? InstallRecord()
        cachedRecord = record
        return record
    }

    private static func save(_ record: InstallRecord) {
        cacheLock.lock()
        cachedRecord = record
        cacheLock.unlock()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(record) else { return }
        try? data.write(to: recordURL, options: .atomic)
    }
}
