import Foundation

/// Takes delivery of a whole pattern library at once — one use case per
/// script file.
///
/// The single-file import in `UseCaseDetailView` imports *into* the use
/// case you're editing, which is the right shape for reworking one
/// animation and the wrong shape for taking delivery of seventy. This
/// creates them instead.
///
/// It lives in the core rather than in the list view that used to own it so
/// the two macOS entry points share one implementation. Everything still
/// goes through `BlenderScriptImporter.apply`, so a folder import and a
/// single import cannot drift: same reading, same recorded streams, same
/// phase timelines.
public enum PatternFolderImport {

    public struct Result {
        public var added = 0
        public var replaced = 0
        /// How many replay the device's own command stream rather than
        /// being interpreted.
        public var exact = 0
        /// How many came in as multi-step timelines.
        public var phased = 0
        /// Files that read fine but aren't patterns — the engine library,
        /// the registry, `__init__.py`.
        public var skipped: [String] = []
        /// Files that couldn't be decoded as text at all. Kept apart from
        /// `skipped` because this one means something is wrong.
        public var unreadable: [String] = []

        public var imported: Int { added + replaced }
    }

    // MARK: - Finding the scripts

    /// Every `.py` under `selection`, which may mix files and folders.
    ///
    /// **Recursive**, unlike the flat scan this replaces. A pattern library
    /// arrives as a zip, and how it lands depends entirely on who expanded
    /// it: Archive Utility drops the files in a folder named after the
    /// archive, while some tools nest them one deeper again. A flat scan of
    /// the folder you were looking at reported "no .py files in that
    /// folder" with the scripts sitting one level down.
    ///
    /// Recursion is why the exclusions below are needed rather than
    /// optional — see `isJunk`.
    public static func scriptURLs(in selection: [URL]) -> [URL] {
        var found: [URL] = []
        let fm = FileManager.default

        for url in selection {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                guard let walker = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }
                for case let file as URL in walker {
                    if isJunkDirectory(file) {
                        walker.skipDescendants()
                        continue
                    }
                    if file.pathExtension.lowercased() == "py", !isJunk(file) {
                        found.append(file)
                    }
                }
            } else if url.pathExtension.lowercased() == "py", !isJunk(url) {
                found.append(url)
            }
        }

        // Deduplicated by path — picking a folder *and* a file inside it is
        // an easy thing to do in a multiple-selection open panel, and
        // importing that file twice would count it twice in the summary.
        var seen = Set<String>()
        return found
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// `._foo.py` is not a Python file.
    ///
    /// It's an AppleDouble sidecar — the resource fork and extended
    /// attributes of `foo.py`, split into a separate file because the
    /// archive format can't carry them inline. They're binary, they end in
    /// `.py`, and every one of them sits next to a real script, so a
    /// recursive scan that doesn't know about them imports the library
    /// twice: once correctly, and once as garbage that reads as no pattern
    /// at all. `__pycache__` is the same problem with `.pyc`, and would be
    /// harmless, but there's no reason to walk it.
    private static func isJunk(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix("._")
    }

    private static func isJunkDirectory(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name == "__MACOSX" || name == "__pycache__" || name == ".git"
    }

    // MARK: - Importing

    /// Imports every script in `urls` into `store`, replacing by name.
    ///
    /// Re-importing a folder is how you pick up a corrected pattern, and
    /// appending turned that into a list with two of everything and no way
    /// to tell which was current. Keeping the existing id means the use
    /// case's timeline file, which is keyed by that id, is overwritten in
    /// place instead of orphaned.
    @MainActor
    public static func run(_ urls: [URL], into store: RingPresetStore) -> Result {
        var result = Result()
        // Collected and appended together at the end rather than added one
        // at a time. `store.add` puts a new animation at the *top* — right
        // for saving one you just made, backwards for a folder: the walk is
        // alphabetical, so inserting each at the top landed the library in
        // reverse, W at the top and A at the bottom.
        var imported: [RingPreset] = []

        for file in urls {
            let fileName = file.lastPathComponent
            guard let (text, _) = BlenderScriptImporter.readScriptFollowingDelegation(at: file) else {
                result.unreadable.append(fileName)
                continue
            }
            // A pattern defines `schedule_<name>`. The support modules that
            // live in the same folder don't — `ripple.py` is motion maths,
            // `pattern_common.py` is the engine library — and a folder
            // import shouldn't turn them into use cases. `ripple.py` in
            // particular reads cleanly as a *scene* script (it has an
            // uppercase `NUM_LEDS`), so without this it imported as a
            // plausible-looking animation with the wrong ring size.
            guard text.contains("def schedule_") else {
                result.skipped.append(fileName)
                continue
            }
            let config = RingConfig()
            let outcome = BlenderScriptImporter.apply(text, to: config)
            guard !outcome.applied.isEmpty else {
                result.skipped.append(fileName)
                continue
            }

            let name = displayName(for: file)
            let preset: RingPreset
            // Checked against what's already staged as well as what's in
            // the store: two scripts can share a display name, and the
            // second one no longer finds the first in the store, because
            // the first hasn't been appended yet.
            if let existing = (store.presets + imported).first(where: { $0.name == name }) {
                var updated = RingPreset(name: name, config: config)
                updated.id = existing.id
                if store.presets.contains(where: { $0.id == existing.id }) {
                    store.update(updated)
                } else if let index = imported.firstIndex(where: { $0.id == existing.id }) {
                    imported[index] = updated
                }
                preset = updated
                result.replaced += 1
            } else {
                preset = RingPreset(name: name, config: config)
                imported.append(preset)
                result.added += 1
            }
            if config.firmwarePatternStream != nil { result.exact += 1 }

            // A use case's timeline lives in its own store file keyed by the
            // preset's UUID, so writing it means standing up that use case's
            // player and installing into it — the same path the detail view
            // uses when you import into an open use case.
            // Installed even when empty, so a pattern that used to import
            // as phases and no longer does doesn't keep the old steps.
            let player = TimelinePlayer(fileName: TimelinePlayer.useCaseFileName(preset.id))
            player.installImported(outcome.timeline ?? RingTimeline())
            if outcome.timeline != nil { result.phased += 1 }
        }

        // Alphabetical, and by the name on the row rather than by filename
        // — `listen_blue_teal.py` and `Listen Blue Teal` sort the same way
        // here, but nothing guarantees that in general.
        store.append(contentsOf: imported.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        })
        return result
    }

    /// `warble_kaleidoscope_blue.py` → "Warble Kaleidoscope Blue".
    public static func displayName(for file: URL) -> String {
        file.deletingPathExtension().lastPathComponent
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    // MARK: - Reporting

    /// The sentence shown when it's done.
    ///
    /// Skips are *named* rather than counted: they're usually the library
    /// and the registry, and saying which ones they were is the difference
    /// between "as expected" and "something went wrong".
    public static func summary(_ result: Result) -> String {
        var summary: String
        if result.replaced > 0 && result.added > 0 {
            summary = "Added \(result.added), replaced \(result.replaced)."
        } else if result.replaced > 0 {
            summary = "Replaced \(result.replaced) existing use case\(result.replaced == 1 ? "" : "s")."
        } else {
            summary = "Added \(result.added) use case\(result.added == 1 ? "" : "s")."
        }
        if result.exact > 0 {
            summary += " \(result.exact) replay the device's own command stream exactly."
        }
        if result.phased > 0 {
            summary += " \(result.phased) came in as multi-step timelines."
        }
        if !result.skipped.isEmpty {
            // The verb has to agree with the count too — "1 file that
            // aren't patterns" was on screen every time a folder held a
            // single support module, which is most of them.
            let one = result.skipped.count == 1
            summary += "\n\nSkipped \(result.skipped.count) file\(one ? "" : "s")"
                + " that \(one ? "isn't a pattern" : "aren't patterns"): \(result.skipped.joined(separator: ", "))"
        }
        if !result.unreadable.isEmpty {
            summary += "\n\nCouldn't read \(result.unreadable.joined(separator: ", "))"
                + " — not UTF-8, Latin-1, Mac Roman or UTF-16."
        }
        return summary
    }
}
