import Foundation
import RingAnimatorCore

// Runs the app's real import path over a folder of pattern scripts and
// reports, per file, exactly what came back.
//
// This exists because "the import is broken" is a claim about a code path
// that normally only runs behind a file picker, in a signed app, against
// files in iCloud. Every part of that makes a report ambiguous: a file
// that imports nothing looks identical to a file the app couldn't read,
// which looks identical to an app that never reloaded. Running the same
// `BlenderScriptImporter.apply` the buttons call, headlessly, over the
// whole library, turns it into a yes/no with a filename attached.
//
//   swift run ImportCheck [patterns-dir]
//
// Exits non-zero if any file that declares a scheduler imports nothing.

@MainActor
func main() -> Int32 {
    let args = CommandLine.arguments
    let folder: URL
    if args.count > 1 {
        folder = URL(fileURLWithPath: args[1])
    } else {
        folder = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Claude/patterns")
    }

    // The same discovery the app does, so a file the app would never see
    // can't pass here — and one it would see can't be missed here.
    let files = PatternFolderImport.scriptURLs(in: [folder])
    guard !files.isEmpty else {
        FileHandle.standardError.write(Data("No .py files under \(folder.path)\n".utf8))
        return 1
    }

    var patterns = 0, exact = 0, phased = 0, support = 0
    var failures: [String] = []
    var unreadable: [String] = []

    for file in files {
        let name = file.lastPathComponent
        guard let (text, _) = BlenderScriptImporter.readScriptFollowingDelegation(at: file) else {
            unreadable.append(name)
            continue
        }
        // Same discriminators the importer uses. A pattern defines a
        // `schedule_<name>`; the support modules in the same folder don't.
        // `pattern_common.py` does both — it *defines* the `_schedule_*`
        // helpers every pattern calls — and importing nothing from it is
        // correct, not a failure, so it must be recognized here too or it
        // reads as the one file that broke.
        guard text.contains("def schedule_"), !text.contains("def _schedule_") else {
            support += 1
            continue
        }
        patterns += 1
        let config = RingConfig()
        let outcome = BlenderScriptImporter.apply(text, to: config)
        if outcome.applied.isEmpty {
            failures.append(name)
            continue
        }
        let stream = config.firmwarePatternStream != nil
        let steps = outcome.timeline?.segments.count ?? 0
        if stream { exact += 1 }
        if steps > 0 { phased += 1 }
        print(String(
            format: "  %-46@ %@%@",
            name as NSString,
            (stream ? "exact" : "interpreted") as NSString,
            (steps > 0 ? ", \(steps) steps" : "") as NSString
        ))
    }

    print("")
    print("\(patterns) patterns · \(exact) exact · \(phased) phased · \(support) support modules skipped")

    for name in unreadable { print("  UNREADABLE  \(name)") }
    for name in failures { print("  NOTHING IMPORTED  \(name)") }

    if failures.isEmpty && unreadable.isEmpty && patterns > 0 {
        print("Import is working.")
        return 0
    }
    return 1
}

exit(main())
