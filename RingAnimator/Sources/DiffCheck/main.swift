import Foundation
import RingAnimatorCore

// Does the exported Diode Mode compute the same numbers as the app?
//
// `ExportCheck` proves every generated file compiles. That is a different
// question from whether it is *right*: the diode field in
// `CodeGeneratorsDiodeMode` is a hand port of `RingView.diodeIntensity`,
// two implementations of the same maths kept in step by reading them side
// by side. Nothing stopped one from drifting.
//
// So this compiles each export for real, runs it, and compares its
// brightness values against the app's own field over a grid of diodes and
// instants. A mismatch prints the worst offender rather than just a count,
// because "Ripple is out by 0.4 at t=1.5" is a lead and "Ripple failed" is
// not.
//
// `swift run DiffCheck` — run by preflight.sh.

let tolerance = 1e-9
let sampleTimes: [Double] = [0, 0.37, 1.0, 2.5, 4.2]

@MainActor
func run() -> Int32 {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("nexus-diff-check-\(ProcessInfo.processInfo.processIdentifier)")
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dir) }

    var failed = false
    var checked = 0

    for type in RingAnimationType.allCases {
        let config = RingConfig()
        config.animationType = type
        config.diodeModeEnabled = true

        guard let exported = brightnessesFromExport(config: config, type: type, in: dir) else {
            print("  ✗ \(type.rawValue) — the export wouldn't build or run")
            failed = true
            continue
        }

        var worst = 0.0
        var worstAt = ""
        for (timeIndex, time) in sampleTimes.enumerated() {
            let mine = RingView.probeBrightnesses(config: config, elapsed: time)
            let theirs = exported[timeIndex]
            guard mine.count == theirs.count else {
                print("  ✗ \(type.rawValue) — \(mine.count) diodes here, \(theirs.count) exported")
                failed = true
                break
            }
            for (i, (a, b)) in zip(mine, theirs).enumerated() where abs(a - b) > worst {
                worst = abs(a - b)
                worstAt = "diode \(i) at t=\(time): app \(String(format: "%.6f", a)) vs export \(String(format: "%.6f", b))"
            }
        }

        checked += 1
        if worst > tolerance {
            print("  ✗ \(type.rawValue) — off by \(String(format: "%.6f", worst)) — \(worstAt)")
            failed = true
        } else {
            print("  ✓ \(type.rawValue) — matches to \(String(format: "%.0e", tolerance))")
        }
    }

    print("  \(checked) animation types compared at \(sampleTimes.count) instants each")
    return failed ? 1 : 0
}

/// Writes the export, adds a probe and a `main`, compiles, runs, and reads
/// back one line of brightnesses per sampled instant.
@MainActor
func brightnessesFromExport(config: RingConfig, type: RingAnimationType, in dir: URL) -> [[Double]]? {
    let slug = type.rawValue.replacingOccurrences(of: " ", with: "")
    let caseDir = dir.appendingPathComponent(slug)
    try? FileManager.default.createDirectory(at: caseDir, withIntermediateDirectories: true)

    // The generated members are `private`, and an extension in the same
    // file is the only thing that can reach them — so the probe is appended
    // to the generated source rather than written alongside it.
    let generated = CodeGenerators.swiftUICode(config: config) + """


    // Added by DiffCheck.
    extension ThinkingRingView {
        func probeBrightnesses(elapsed: Double) -> [Double] {
            let count = max(diodeCount, 2)
            let phase = easedPhase(elapsed: elapsed)
            return (0..<count).map { i in
                diodeState(index: i, phase: phase, elapsed: elapsed, colors: ringColors).brightness
            }
        }
    }
    """

    let mainSource = """
    import SwiftUI

    let view = ThinkingRingView()
    for t in [\(sampleTimes.map { String($0) }.joined(separator: ", "))] {
        print(view.probeBrightnesses(elapsed: t).map { String($0) }.joined(separator: ","))
    }
    """

    let generatedURL = caseDir.appendingPathComponent("Generated.swift")
    let mainURL = caseDir.appendingPathComponent("main.swift")
    let binary = caseDir.appendingPathComponent("probe")
    try? generated.write(to: generatedURL, atomically: true, encoding: .utf8)
    try? mainSource.write(to: mainURL, atomically: true, encoding: .utf8)

    let compile = Process()
    compile.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    compile.arguments = ["swiftc", "-O", generatedURL.path, mainURL.path, "-o", binary.path]
    let compileErr = Pipe()
    compile.standardError = compileErr
    compile.standardOutput = Pipe()
    try? compile.run()
    compile.waitUntilExit()
    guard compile.terminationStatus == 0 else {
        let message = String(data: compileErr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        for line in message.components(separatedBy: "\n").filter({ $0.contains("error:") }).prefix(2) {
            print("      \(line.trimmingCharacters(in: .whitespaces))")
        }
        return nil
    }

    let runProcess = Process()
    runProcess.executableURL = binary
    let out = Pipe()
    runProcess.standardOutput = out
    runProcess.standardError = Pipe()
    try? runProcess.run()
    runProcess.waitUntilExit()
    guard runProcess.terminationStatus == 0,
          let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    else { return nil }

    return text
        .components(separatedBy: "\n")
        .filter { !$0.isEmpty }
        .map { $0.components(separatedBy: ",").compactMap(Double.init) }
}

print("exported diode field against the app's:")
exit(run())
