import Foundation
import RingAnimatorCore

// Generates every SwiftUI export the app can produce and typechecks each
// one with swiftc.
//
// This exists because the generators emit *strings*. The package builds
// happily no matter what those strings say, so a generated file that
// doesn't compile is invisible until someone pastes it into Xcode. Four
// such bugs shipped before this check was written — the particles
// function (present in every export), Multi Chase, and two cue styles —
// all the same trap: `var`, `for`, and deferred-initialization `if/else`
// are not allowed inside a `@ViewBuilder` closure.
//
// Run with `swift run ExportCheck`. Exits non-zero if anything fails, so
// it can gate a release.
//
// Only SwiftUI is covered. The Kotlin and JavaScript generators emit the
// same shapes and are likely to carry the same class of bug, but
// checking them needs kotlinc and node — see CLAUDE.md.

@MainActor
func main() -> Int32 {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("nexus-export-check-\(ProcessInfo.processInfo.processIdentifier)")
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dir) }

    var files: [(name: String, url: URL)] = []

    // Particles on throughout: the particles function is emitted into
    // every export and was itself broken, so leaving it off would have
    // hidden the most widespread of the four bugs.
    for type in RingAnimationType.allCases {
        let config = RingConfig()
        config.animationType = type
        config.particlesEnabled = true
        let name = "Anim_" + type.rawValue.replacingOccurrences(of: " ", with: "")
        let url = dir.appendingPathComponent(name + ".swift")
        try? CodeGenerators.swiftUICode(config: config).write(to: url, atomically: true, encoding: .utf8)
        files.append((name, url))
    }

    // A second pass over every type with the options that used to be
    // absent from the exports entirely — extra colors, Diode Mode, and a
    // non-round diode shape. Without this the new code paths are emitted
    // by nothing the check ever compiles, which is how four broken exports
    // shipped the first time: the generators emit *strings*, so an
    // un-exercised branch is invisible until someone pastes it into Xcode.
    for type in RingAnimationType.allCases {
        for shape in DiodeShape.allCases {
            let config = RingConfig()
            config.animationType = type
            config.particlesEnabled = true
            config.additionalColors = [.green, .orange]
            config.diodeModeEnabled = true
            config.diodeShape = shape
            let name = "Diode_" + type.rawValue.replacingOccurrences(of: " ", with: "")
                + "_" + shape.rawValue.replacingOccurrences(of: " ", with: "")
            let url = dir.appendingPathComponent(name + ".swift")
            try? CodeGenerators.swiftUICode(config: config).write(to: url, atomically: true, encoding: .utf8)
            files.append((name, url))
        }
    }

    if let cue = LEDCueLibrary.all.first {
        for style in LEDPatternStyle.allCases {
            var params = cue.defaultParameters
            params.style = style
            params.particlesEnabled = true
            let name = "Cue_" + style.rawValue.replacingOccurrences(of: " ", with: "")
            let url = dir.appendingPathComponent(name + ".swift")
            try? CodeGenerators.swiftUICueCode(cue: cue, parameters: params).write(to: url, atomically: true, encoding: .utf8)
            files.append((name, url))
        }
    }

    guard let sdk = run("/usr/bin/xcrun", ["--show-sdk-path", "--sdk", "macosx"])?
        .trimmingCharacters(in: .whitespacesAndNewlines), !sdk.isEmpty else {
        print("ExportCheck: couldn't locate the macOS SDK via xcrun.")
        return 1
    }

    var failed: [String] = []
    for file in files {
        let output = run("/usr/bin/xcrun", [
            "swiftc", "-parse-as-library",
            "-sdk", sdk,
            "-target", "arm64-apple-macos14",
            "-typecheck", file.url.path
        ]) ?? ""
        if output.contains("error:") {
            failed.append(file.name)
            print("FAIL  \(file.name)")
            for line in output.split(separator: "\n").filter({ $0.contains("error:") }).prefix(3) {
                print("      \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
    }

    print("──")
    print("\(files.count - failed.count) passed, \(failed.count) failed")
    return failed.isEmpty ? 0 : 1
}

/// Runs a tool and returns stdout+stderr combined.
func run(_ launchPath: String, _ arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do { try process.run() } catch { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(data: data, encoding: .utf8)
}

exit(main())
