import Foundation
import RingAnimatorCore

// Replaces the Use Cases library from a folder of firmware pattern
// scripts — the first half of cutting a new bundled library, with
// `refresh-library.sh` as the second.
//
// The app can already import a folder; what it can't do is clear the
// library first, and doing that by hand across seventy rows is the kind
// of job that gets done wrong once. So this exists, and it is deliberately
// awkward to run: it destroys whatever is in Use Cases now, so it wants
// --replace-everything spelled out and refuses without it.
//
//   swift run LibraryImport --folder ~/…/patterns --replace-everything
//
// It takes its own backup regardless, next to the store, because "I meant
// the other folder" is a thing people say.

@MainActor
func run() -> Int32 {
    let arguments = CommandLine.arguments
    guard let folderIndex = arguments.firstIndex(of: "--folder"),
          folderIndex + 1 < arguments.count else {
        print("usage: LibraryImport --folder <path> [--replace-everything]")
        return 2
    }
    let folder = URL(fileURLWithPath: (arguments[folderIndex + 1] as NSString).expandingTildeInPath)
    let replace = arguments.contains("--replace-everything")

    let files = PatternFolderImport.scriptURLs(in: [folder])
    guard !files.isEmpty else {
        print("No .py files under \(folder.path)")
        return 1
    }

    let store = RingPresetStore(fileName: "use-cases.json")
    print("folder:   \(folder.path)")
    print("scripts:  \(files.count)")
    print("in app:   \(store.presets.count) use cases")

    guard replace else {
        print("\nNothing done. Add --replace-everything to clear those \(store.presets.count) and import these \(files.count).")
        return 0
    }

    // A dated copy beside the store, not in a temp directory that gets
    // cleaned up by the OS a week from now.
    let support = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/RingAnimator")
    let stamp = ISO8601DateFormatter()
    stamp.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
    let backup = support.appendingPathComponent("use-cases-before-import-\(stamp.string(from: Date()).replacingOccurrences(of: ":", with: "")).json")
    try? FileManager.default.copyItem(at: support.appendingPathComponent("use-cases.json"), to: backup)
    print("backup:   \(backup.lastPathComponent)")

    // Each use case owns a timeline file keyed by its id. Deleting the use
    // case without it leaves an orphan in Application Support that nothing
    // will ever collect — the app's own delete does this too.
    for preset in store.presets {
        TimelinePlayer.deleteStore(fileName: TimelinePlayer.useCaseFileName(preset.id))
        store.delete(preset.id)
    }
    print("cleared:  \(store.presets.count) remaining")

    let result = PatternFolderImport.run(files, into: store)
    print("\n" + PatternFolderImport.summary(result))
    print("\nnow: \(store.presets.count) use cases")
    if !result.skipped.isEmpty {
        print("skipped (\(result.skipped.count)):")
        for name in result.skipped.prefix(10) { print("  - \(name)") }
    }
    if !result.unreadable.isEmpty {
        print("unreadable (\(result.unreadable.count)):")
        for name in result.unreadable.prefix(10) { print("  - \(name)") }
    }
    return result.imported > 0 ? 0 : 1
}

exit(run())
