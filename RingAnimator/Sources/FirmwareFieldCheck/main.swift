import Foundation
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
    for led in 0..<16 {
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
if failures == 0 {
    print("✅ every field reproduces the firmware exactly")
    exit(0)
}
print("❌ \(failures) pattern(s) no longer match the firmware")
exit(1)
