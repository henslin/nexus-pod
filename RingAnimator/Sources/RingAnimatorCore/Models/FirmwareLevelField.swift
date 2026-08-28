import Foundation

/// The firmware's own per-LED level functions, ported exactly.
///
/// Twenty-one of the patterns in the `patterns/` library are built on one
/// shared engine, `_schedule_level_threshold`. It takes a `level(i, t_s)`
/// closure — a pure function of LED index and time — samples it every
/// `tick_ms` for every LED, and writes one of two palette registers
/// depending on whether the sample cleared a threshold:
///
/// ```python
/// bits = 0x07 if level(i, t_s) >= threshold else 0x00
/// ```
///
/// That is the whole rendering model, and it is reproducible here exactly
/// rather than approximately. `RingView` already evaluates every animation
/// as a scalar field over (diode, time) — the same shape — so these drop
/// straight in. Before this, a pattern like `voiceprint_shimmer_blue`
/// imported as "Sparkle, blue-ish", which was the right *kind* of thing and
/// none of the actual motion.
///
/// ## Two colors, both lit
///
/// The engine never deselects an LED: it opens with
/// `select_all_leds(True, 0x00)` and only ever flips which register an LED
/// reads. So every diode is always at full brightness and the field picks
/// its *color*, not its intensity. A diode below threshold shows Color0, at
/// or above it shows Color1. There is no ramp between them — the
/// quantization is what gives these patterns their crisp edges, and
/// smoothing it would be a prettier animation than the device can produce.
///
/// ## Fidelity notes
///
/// - Parameters are the values the closures actually capture, read out of
///   `__closure__` rather than transcribed by eye.
/// - `roundHalfToEven` is Python's `round`, which is banker's rounding and
///   differs from Swift's `rounded()` at exactly the half-integers
///   `strobe_pulsing_lattice_red` hits (`i / step` lands on 0.5 and 2.5 for
///   a 16-LED ring with 4 anchors, where the two disagree).
/// - `pmod` is Python's `%`, which takes the sign of the divisor. Every
///   call site here has positive operands, but the helper keeps the port
///   honest rather than relying on that staying true.
///
/// Every case is checked against the real Python over a 16 x 40 grid of
/// (LED, time) samples — see the differential test in `Tests`.
public enum FirmwareLevelField: String, Codable, CaseIterable, Sendable {
    case braidedTwist
    case cellularAutomaton
    case flockingDrift
    case micLevelJitter
    case pendulumSwing
    case quantumTunneling
    case resonantPingDecay
    case ribbonPhaseWarp
    case speakingWaveform
    case strobePulsingLattice
    case tidalModulation
    case utteranceEnvelope
    case voiceprintShimmer
    case wakeBloomTrioGaps
    case wakeBloomWaiting
    case warbleKaleidoscope

    /// The ring these were all written for.
    private static let totalLEDs: Double = 16

    /// The threshold each pattern passes to the engine. Mostly the 0.5
    /// default, but three override it and those three look wrong at 0.5.
    public var threshold: Double {
        switch self {
        case .speakingWaveform: return 0.42
        case .strobePulsingLattice: return 0.55
        case .utteranceEnvelope: return 0.35
        default: return 0.5
        }
    }

    /// The loop the pattern is authored over. Several of these declare no
    /// `DURATION_MS`, so this is the only place the real figure appears.
    public var loopSeconds: Double {
        switch self {
        case .braidedTwist: return 10
        case .cellularAutomaton: return 32.0 / 3.0
        case .flockingDrift: return 12
        case .micLevelJitter: return 8
        case .pendulumSwing: return 10
        case .quantumTunneling: return 8
        case .resonantPingDecay: return 10.4
        case .ribbonPhaseWarp: return 10
        case .speakingWaveform: return 8.8
        case .strobePulsingLattice: return 10.0 / 3.0
        case .tidalModulation: return 20
        case .utteranceEnvelope: return 10.2
        case .voiceprintShimmer: return 10
        case .wakeBloomTrioGaps: return 8
        case .wakeBloomWaiting: return 8
        case .warbleKaleidoscope: return 10
        }
    }

    /// The engine samples on a 100 ms tick.
    public var tickMs: Double { 100 }

    public var displayName: String {
        switch self {
        case .braidedTwist: return "Braided Twist"
        case .cellularAutomaton: return "Cellular Automaton"
        case .flockingDrift: return "Flocking Drift"
        case .micLevelJitter: return "Mic Level Jitter"
        case .pendulumSwing: return "Pendulum Swing"
        case .quantumTunneling: return "Quantum Tunneling"
        case .resonantPingDecay: return "Resonant Ping Decay"
        case .ribbonPhaseWarp: return "Ribbon Phase Warp"
        case .speakingWaveform: return "Speaking Waveform"
        case .strobePulsingLattice: return "Pulsing Lattice"
        case .tidalModulation: return "Tidal Modulation"
        case .utteranceEnvelope: return "Utterance Envelope"
        case .voiceprintShimmer: return "Voiceprint Shimmer"
        case .wakeBloomTrioGaps: return "Wake Bloom Trio Gaps"
        case .wakeBloomWaiting: return "Wake Bloom Waiting"
        case .warbleKaleidoscope: return "Warble Kaleidoscope"
        }
    }

    // MARK: - The fields

    /// `level(i, t_s)` — the LED's raw level before thresholding.
    public func level(index: Int, time t: Double) -> Double {
        let i = Double(index)
        let n = Self.totalLEDs

        switch self {
        case .warbleKaleidoscope:
            // folds 4, inner_cycles 1, speed_hz 0.6
            let folds = 4.0, innerCycles = 1.0, speedHz = 0.6
            let segLen = n / folds
            var folded = pmod(i, segLen) / segLen
            if Int(i / segLen) % 2 == 1 { folded = 1 - folded }
            return 0.5 + 0.5 * sin(folded * 2 * .pi * innerCycles - t * speedHz * 2 * .pi)

        case .braidedTwist:
            // twists 2, speed_hz 0.3
            let strand = (i / n) * 2 * .pi * 2 - t * 0.3 * 2 * .pi
            return cos(strand) >= 0 ? 1 : 0

        case .wakeBloomWaiting:
            // speed_hz 0.25, shimmer_speed 0.9
            let base = 0.5 + 0.5 * sin(pmod(t * 0.25, 1) * 2 * .pi)
            let shimmer = 0.15 * sin(2 * .pi * (i / n) * 3 + t * 0.9 * 2 * .pi)
            return max(0, min(1, base + shimmer))

        case .wakeBloomTrioGaps:
            // speed_leds_per_s 4.0, gap_half_width 1.5, n_arcs 3
            let pos = pmod(t * 4.0, n)
            return inAnyArc(i: i, pos: pos, halfWidth: 1.5, arcs: 3) ? 0 : 1

        case .voiceprintShimmer:
            // shimmer_speed 1.6
            let basePattern = hash01(i, 41)
            let shimmer = 0.15 * sin(t * 1.6 * 2 * .pi + i * 0.7)
            return max(0, min(1, basePattern * 0.8 + shimmer))

        case .pendulumSwing:
            // speed_hz 0.2, amp 5.0, width 2.6
            let pos = (n / 2) + sin(t * 0.2 * 2 * .pi) * 5.0
            let d = abs(i - pos)
            return d < 2.6 ? cos((d / 2.6) * .pi / 2) : 0

        case .tidalModulation:
            // slow_cycles 1, slow_speed 0.12, fast_cycles 5, fast_speed 0.55
            let slow = 0.5 + 0.5 * sin(2 * .pi * (i / n) * 1 - t * 0.12 * 2 * .pi)
            let fast = 0.5 + 0.5 * sin(2 * .pi * (i / n) * 5 - t * 0.55 * 2 * .pi)
            return slow * (0.4 + 0.6 * fast)

        case .ribbonPhaseWarp:
            // speed_hz 0.28, warp_amt 1.6, warp_freq 2.5, warp_speed 1.1
            let base = (i / n) - t * 0.28
            let warped = sin(base * 2 * .pi + 1.6 * sin(base * 2 * .pi * 2.5 + t * 1.1))
            return 0.5 + 0.5 * warped

        case .resonantPingDecay:
            // period 2.6, damping 1.3, freq 1.8
            let age = (pmod(t, 2.6) / 2.6) * 2.6
            let ping = exp(-age * 1.3) * cos(age * 1.8 * 2 * .pi)
            return max(0, 0.5 + 0.5 * ping)

        case .cellularAutomaton:
            // gen_speed 6, gen_period 64 — a Sierpinski rule on the index bits.
            let g = Int(t * 6) % 64
            return (index & g) == index ? 1 : 0

        case .quantumTunneling:
            // jump_rate 0.9, wiggle_speed 2.5, wiggle_amt 0.6, width 1.6
            let seed = floor(t * 0.9)
            let frac = pmod(t * 0.9, 1)
            let pos = pmod(hash01(seed, 1) * n + sin(t * 2.5 * 2 * .pi + seed) * 0.6, n)
            var lvl = ringDistance(i, pos) < 1.6 ? 1.0 : 0.0
            if frac < 0.08 { lvl = min(1, lvl + 0.4) }
            return lvl

        case .strobePulsingLattice:
            // anchors 4, speed_hz 1.8, phase_spread 1.4
            let anchors = 4.0
            let step = n / anchors
            // Python's `round` is banker's rounding; `i / step` lands on
            // 0.5 and 2.5 here, where half-away-from-zero disagrees.
            let idx = pmod(roundHalfToEven(i / step), anchors)
            let d = ringDistance(i, idx * step)
            let localPulse = 0.5 + 0.5 * sin(t * 1.8 * 2 * .pi - idx * 1.4)
            let falloff = max(0, 1 - d / (step / 1.4))
            return localPulse * falloff

        case .speakingWaveform:
            // word_period 1.1, bars 3, speed_hz 0.5
            let wordIdx = floor(t / 1.1)
            let wfrac = pmod(t, 1.1) / 1.1
            let env = sin(min(1, wfrac) * .pi)
            let bar = 0.5 + 0.5 * sin(2 * .pi * (i / n) * 3 + t * 0.5 * 2 * .pi + hash01(wordIdx, i) * 2)
            return max(0, env) * bar

        case .utteranceEnvelope:
            // utt_period 3.4, lag_amt 0.5, sub_pulses 4
            let ph = pmod(t, 3.4) / 3.4
            let phLag = max(0, min(1, ph - (i / n) * 0.5))
            return pow(max(0, sin(phLag * .pi)), 0.6) * (0.6 + 0.4 * sin(phLag * .pi * 4))

        case .micLevelJitter:
            // speed_hz 0.294 — three weighted harmonics, then a per-LED offset.
            var acc = 0.0
            var wsum = 0.0
            for k in 0..<3 {
                let w = 1.0 / Double(k + 1)
                acc += w * (0.5 + 0.5 * sin(t * 0.294 * Double(k + 1) * 1.7 * 2 * .pi
                                            + hash01(Double(k), 3) * 10))
                wsum += w
            }
            acc /= wsum
            let off = hash01(i, 1) * 0.25
            return max(0, acc - off * (1 - acc))

        case .flockingDrift:
            // dot_count 3, speed_hz 0.15, spread 0.35, width 2.4
            var best = 0.0
            for k in 0..<3 {
                let sp = 0.15 * (1 + Double(k) * 0.35)
                let pos = pmod(t * sp, 1) * n
                best = max(best, max(0, 1 - ringDistance(i, pos) / 2.4))
            }
            return best
        }
    }

    /// Whether this LED reads Color1 rather than Color0 at this instant —
    /// the engine's own `level >= threshold` test.
    public func isLit(index: Int, time: Double) -> Bool {
        level(index: index, time: time) >= threshold
    }

    // MARK: - Ported primitives

    /// `_hash01` — deterministic pseudo-random 0..1.
    private func hash01(_ i: Double, _ seed: Double) -> Double {
        let x = sin(i * 127.1 + seed * 311.7) * 43758.5453
        return x - floor(x)
    }

    /// `_ring_distance` — shortest way round a 16-LED circle.
    private func ringDistance(_ i: Double, _ pos: Double) -> Double {
        let d = abs(i - pos)
        return min(d, Self.totalLEDs - d)
    }

    /// `_in_any_arc` — inside any of `arcs` equal arcs centered on `pos`.
    private func inAnyArc(i: Double, pos: Double, halfWidth: Double, arcs: Int) -> Bool {
        for a in 0..<arcs {
            let c = pmod(pos + Double(a) * Self.totalLEDs / Double(arcs), Self.totalLEDs)
            if ringDistance(i, c) < halfWidth { return true }
        }
        return false
    }

    /// Python's `%`, which takes the sign of the divisor.
    private func pmod(_ a: Double, _ b: Double) -> Double {
        let r = a.truncatingRemainder(dividingBy: b)
        return r < 0 ? r + b : r
    }

    /// Python's `round` — half to even, not half away from zero.
    private func roundHalfToEven(_ x: Double) -> Double {
        x.rounded(.toNearestOrEven)
    }
}
