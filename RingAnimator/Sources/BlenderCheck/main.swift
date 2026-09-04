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

/// Whether the emitted chain actually dispatches on `value`.
///
/// Two forms, and missing the second one cost a false positive and two
/// unreachable branches committed on the strength of it: a case can have
/// its own `x == "value"` test, or share one with its neighbours as
/// `x in ("a", "b")`. Both are branches; only the first is an equality.
///
/// Deliberately not a check that the params dict *mentions* the value —
/// every script names its own style at the top, so that would pass for
/// every case whether or not the chain handles it.
func hasBranch(for value: String, variable: String, in code: String) -> Bool {
    if code.contains("\(variable) == \"\(value)\"") { return true }
    // A shared branch: `style in ("off", "notApplicable"):`
    for line in code.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("if \(variable) in (")
            || trimmed.hasPrefix("elif \(variable) in (") else { continue }
        if trimmed.contains("\"\(value)\"") { return true }
    }
    return false
}

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
        if !hasBranch(for: type.rawValue, variable: "anim", in: code) {
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
        if !hasBranch(for: style.rawValue, variable: "style", in: code) {
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
