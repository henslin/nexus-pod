import Foundation
import RingAnimatorCore

// Dumps every Blender script the generators can produce, one file per case.
//
// `ExportCheck` typechecks the SwiftUI exports; nothing checks these. The
// Blender output is a Python heredoc whose `if anim == "..."` chain is
// hand-mirrored from Swift enums, so the failure mode is a new enum case
// silently having no branch — invisible until someone runs the script in
// Blender and reads the console.
//
//   swift run BlenderCheck <out-dir>
//
// Two jobs. As a *check* it asserts every case reaches its own branch
// rather than the fallback. As a *dump* it writes the scripts out so a
// refactor of the generator can be shown to change nothing.

@MainActor
func main() -> Int32 {
    let out = CommandLine.arguments.count > 1
        ? URL(fileURLWithPath: CommandLine.arguments[1])
        : FileManager.default.temporaryDirectory.appendingPathComponent("blender-dump")
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

    var missing: [String] = []

    for type in RingAnimationType.allCases {
        let config = RingConfig()
        config.animationType = type
        let code = CodeGenerators.blenderCode(config: config)
        let name = "anim-" + type.rawValue.replacingOccurrences(of: " ", with: "-")
        try? code.write(to: out.appendingPathComponent(name + ".py"), atomically: true, encoding: .utf8)
        // The branch has to exist in the emitted chain, not merely be named
        // in the params dict at the top.
        if !code.contains("anim == \"\(type.rawValue)\"") {
            missing.append("animation type '\(type.rawValue)'")
        }
    }

    guard let sampleCue = LEDCueLibrary.all.first else {
        print("no cues in the library")
        return 1
    }
    for style in LEDPatternStyle.allCases {
        var parameters = LEDCueParameters(style: style)
        parameters.primaryColorHex = "#2E7BFF"
        let code = CodeGenerators.blenderCueCode(cue: sampleCue, parameters: parameters)
        let name = "style-" + style.rawValue.replacingOccurrences(of: " ", with: "-")
        try? code.write(to: out.appendingPathComponent(name + ".py"), atomically: true, encoding: .utf8)
        if !code.contains("style == \"\(style.rawValue)\"") {
            missing.append("pattern style '\(style.rawValue)'")
        }
    }

    let total = RingAnimationType.allCases.count + LEDPatternStyle.allCases.count
    print("\(total) Blender scripts written to \(out.path)")
    guard missing.isEmpty else {
        print("")
        for name in missing {
            print("  NO BLENDER BRANCH  \(name) — falls through to the generic stand-in")
        }
        return 1
    }
    print("every animation type and pattern style has its own Blender branch")
    return 0
}

exit(main())
