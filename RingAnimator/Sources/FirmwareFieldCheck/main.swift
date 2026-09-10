import Foundation
import SwiftUI
import AppKit
import RingAnimatorCore

// Verifies that every `FirmwareLevelField` still reproduces the firmware's
// own `level(i, t_s)` exactly.
//
// `firmware-levels.json` is ground truth captured from the real Python: the
// engine's `_schedule_level_threshold` is stubbed to grab each pattern's
// closure, which is then sampled over a 16 x 40 grid of (LED, time) and
// written out at full precision. Regenerate it with
// `python3 dump_reference.py firmware-levels.json` from a checkout of the
// `patterns/` library — the fixture is committed so this check runs without
// one.
//
// The check is exact, not approximate. These fields feed a hard threshold,
// so a difference in the last bit is not cosmetic: it flips a diode between
// the two palette registers and the pattern visibly differs. A tolerance
// here would defeat the point of having ported the maths at all — and the
// port really is bit-identical, so there is nothing to tolerate.
//
// Not part of the app; `swift run FirmwareFieldCheck` before a release.

/// The ring both fixtures were recorded at. Changing the hardware count
/// means regenerating them, not editing this — see the scripts alongside.
let ringLEDs = 20

let mapping: [String: FirmwareLevelField] = [
    "braided_twist_green": .braidedTwist,
    "braided_twist_red": .braidedTwist,
    "cellular_automaton_green": .cellularAutomaton,
    "flocking_drift_connection_green": .flockingDrift,
    "mic_level_jitter_listening_blue": .micLevelJitter,
    "pendulum_swing_deterrence_red": .pendulumSwing,
    "quantum_tunneling_speaking_blue": .quantumTunneling,
    "resonant_ping_decay_occupancy_green": .resonantPingDecay,
    "ribbon_phase_warp_red": .ribbonPhaseWarp,
    "speaking_response_waveform_blue": .speakingWaveform,
    "strobe_pulsing_lattice_red": .strobePulsingLattice,
    "tidal_modulation_loading_green": .tidalModulation,
    "utterance_loudness_envelope_blue": .utteranceEnvelope,
    "voiceprint_shimmer_blue": .voiceprintShimmer,
    "wake_bloom_trio_gaps_green": .wakeBloomTrioGaps,
    "wake_bloom_waiting_blue_navy_cobalt": .wakeBloomWaiting,
    "wake_bloom_waiting_blue_steel_ice": .wakeBloomWaiting,
    "warble_kaleidoscope_amber": .warbleKaleidoscope,
    "warble_kaleidoscope_blue": .warbleKaleidoscope,
    "warble_kaleidoscope_green": .warbleKaleidoscope,
    "warble_kaleidoscope_red": .warbleKaleidoscope,
]

struct Reference: Decodable {
    let threshold: Double
    let tick_ms: Double
    let loop_seconds: Double
    let grid: [Double]
}

let fixture = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("firmware-levels.json")

guard let data = try? Data(contentsOf: fixture),
      let references = try? JSONDecoder().decode([String: Reference].self, from: data) else {
    print("❌ couldn't read \(fixture.path)")
    exit(1)
}

var failures = 0
var samples = 0

for (module, reference) in references.sorted(by: { $0.key < $1.key }) {
    guard let field = mapping[module] else {
        print("❌ \(module): no FirmwareLevelField mapped")
        failures += 1
        continue
    }

    var maxDelta = 0.0
    var litMismatches = 0
    var index = 0
    for led in 0..<ringLEDs {
        for step in 0..<40 {
            let time = Double(step) * 0.25
            let mine = field.level(index: led, time: time)
            let theirs = reference.grid[index]
            index += 1
            maxDelta = max(maxDelta, abs(mine - theirs))
            // What actually reaches the screen is the thresholded bit.
            if (mine >= reference.threshold) != (theirs >= reference.threshold) {
                litMismatches += 1
            }
            samples += 1
        }
    }

    var problems: [String] = []
    if maxDelta != 0 { problems.append(String(format: "level differs by %.3e", maxDelta)) }
    if litMismatches > 0 { problems.append("\(litMismatches) lit-state mismatches") }
    if field.threshold != reference.threshold {
        problems.append("threshold \(field.threshold) vs \(reference.threshold)")
    }
    if abs(field.loopSeconds - reference.loop_seconds) > 0.005 {
        problems.append("loop \(field.loopSeconds)s vs \(reference.loop_seconds)s")
    }
    if field.tickMs != reference.tick_ms {
        problems.append("tick \(field.tickMs)ms vs \(reference.tick_ms)ms")
    }

    if problems.isEmpty {
        print("✅ \(module)")
    } else {
        print("❌ \(module): \(problems.joined(separator: ", "))")
        failures += 1
    }
}

print("\n\(samples) samples across \(references.count) patterns")

// --- Part two: the recorded command streams.
//
// Every pattern's scheduler was run against a recorder that captured each
// set_color / select_led call with its timestamp, then replayed to per-LED
// state on a 100 ms grid. `FirmwarePatternStream` has to reproduce that
// replay exactly — it ships the same events, so any difference is a bug in
// how they are being applied, not in the data.

struct RecordedFrame: Decodable {
    let t: Double
    let c0: [Int]
    let c1: [Int]
    let bits: [Int]
    let sel: [Int]
    /// Non-nil per LED for the snapshot-native patterns, which carry a
    /// brightness field rather than a two-register choice.
    let rgb: [[Int]?]?
}
struct RecordedPattern: Decodable {
    let total_ms: Double
    let tick_ms: Double
    let frames: [RecordedFrame]
}

let framesFixture = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("firmware-frames.json")

guard let frameData = try? Data(contentsOf: framesFixture),
      let recorded = try? JSONDecoder().decode([String: RecordedPattern].self, from: frameData) else {
    print("❌ couldn't read \(framesFixture.path)")
    exit(1)
}

/// Takes components directly now that `Frame` carries them.
///
/// It used to build an `NSColor` and convert to sRGB. The components were
/// already sRGB — `FirmwarePatternStream` writes them as
/// `Color(red:green:blue:)`, which is sRGB — so the round trip was
/// identity, and this comparison is against committed fixtures, which is
/// what would say so if it weren't.
func channels(_ rgb: RGB) -> [Int] {
    return [
        Int((rgb.red * 255).rounded()),
        Int((rgb.green * 255).rounded()),
        Int((rgb.blue * 255).rounded()),
    ]
}

var streamFailures = 0
var ledFrames = 0

for (name, reference) in recorded.sorted(by: { $0.key < $1.key }) {
    guard let stream = FirmwarePatternStream.stream(named: name) else {
        print("❌ \(name): missing from the shipped stream library")
        streamFailures += 1
        continue
    }
    var mismatches = 0
    for frame in reference.frames {
        // One pass only. The wrap point is a boundary the two sides define
        // differently and it isn't part of the animation.
        guard frame.t < reference.total_ms else { continue }
        let mine = stream.commandedFrame(atSeconds: frame.t / 1000, ledCount: ringLEDs)
        for led in 0..<ringLEDs {
            let explicit = frame.rgb?[led]
            let expected: [Int]? = explicit ?? (frame.sel[led] == 0
                ? nil
                : (frame.bits[led] == 0 ? frame.c0 : frame.c1))
            if expected != mine.leds[led].map(channels) { mismatches += 1 }
        }
        ledFrames += ringLEDs
    }
    if mismatches > 0 {
        print("❌ \(name): \(mismatches) LED-frame mismatches")
        streamFailures += 1
    }
}

print("\(ledFrames) LED-frames across \(recorded.count) recorded streams")

// MARK: - The fade engine
//
// The commands above are only half the picture. The ring holds two colour
// registers, so any pattern showing more than two colours at once builds
// them out of the fade engine: Color1 is rewritten every tick, and each LED
// that drops out ramps toward black along a hue-preserving line, freezing at
// whatever was live when it was deselected. Ignoring that — which the
// replay used to — rendered a 120-hue rainbow as two colours.
//
// So: the rainbows have to show a rainbow, and the patterns that switch
// pixels off still have to go dark.

@MainActor
func distinctLitColours(_ stream: FirmwarePatternStream, atMs t: Double) -> Int {
    let frame = stream.frame(atSeconds: t / 1000, ledCount: ringLEDs)
    var seen: Set<String> = []
    for led in frame.leds {
        guard let led, let parts = channels(led) as [Int]? else { continue }
        seen.insert(parts.map(String.init).joined(separator: ","))
    }
    return seen.count
}

var fadeFailures = 0
@MainActor
func fadeCheck(_ label: String, _ ok: Bool, _ detail: String) {
    print("\(ok ? "✅" : "❌") \(label) — \(detail)")
    if !ok { fadeFailures += 1 }
}

for name in ["spinning_rainbow", "spinning_rainbow_quad"] {
    guard let stream = FirmwarePatternStream.stream(named: name) else { continue }
    let total = Double(stream.totalMs)
    let peak = stride(from: 0.0, to: total, by: 100).map { distinctLitColours(stream, atMs: $0) }.max() ?? 0
    let registers = Set(stream.events.filter { $0.kind == 1 }.map { "\($0.a),\($0.b),\($0.c)" }).count
    fadeCheck("\(name) shows its hues", peak > 2,
              "\(peak) colours lit at once, out of \(registers) the pattern walks through")
}

// The other direction: a pattern built on hard on/off edges must still go
// fully dark, or "fade" has become "everything smears".
if let alarm = FirmwarePatternStream.stream(named: "alarm_sos") {
    let total = Double(alarm.totalMs)
    let darkFrames = stride(from: 0.0, to: total, by: 50)
        .filter { distinctLitColours(alarm, atMs: $0) == 0 }.count
    fadeCheck("alarm_sos still goes dark between flashes", darkFrames > 0,
              "\(darkFrames) fully dark frames")
}

if fadeFailures > 0 { failures += fadeFailures }


if failures == 0 && streamFailures == 0 {
    print("\n✅ every field and every stream reproduces the firmware exactly")
    exit(0)
}
print("\n❌ \(failures) field(s) and \(streamFailures) stream(s) no longer match the firmware")
exit(1)

