import SwiftUI

/// A firmware pattern's literal command stream, replayed.
///
/// `FirmwareLevelField` reproduces the twenty-one patterns built on the
/// shared level-threshold engine, whose maths is a closed form worth
/// porting. The rest schedule LED commands directly — comets stepping head
/// and tail, cascades filling frame by frame, Perlin fields sampled per
/// tick, palette rewrites mid-animation — and there is no closed form to
/// port. Forty-five distinct hand-written bodies is not a thing to
/// transcribe; and transcribing it would only ever *approach* what the
/// recording already is.
///
/// So this ships the commands themselves. Each pattern's scheduler is run
/// once, offline, against a recorder that captures every `set_color0` /
/// `set_color1` / `select_led` / `select_all_leds` call with its timestamp
/// — the exact byte stream the device receives. Replaying it here is not a
/// reproduction of the animation; it *is* the animation.
///
/// ## What a frame means
///
/// The hardware holds two palette registers and, per LED, a selection bit
/// and a register choice:
///
/// - not selected → dark
/// - selected, bits `0x00` → Color0
/// - selected, bits `0x07` → Color1
///
/// "Off" in these patterns is usually Color0 being black rather than a
/// deselect, which is why both paths have to be honored rather than
/// treating `0x00` as off.
///
/// ## Regenerating
///
/// `Sources/FirmwareFieldCheck/record_streams.py` runs every pattern
/// against the recorder and writes `firmware-streams.json`. Re-run it when
/// the pattern library changes. The resource is committed so neither the
/// app nor its checks need a copy of the library.
public struct FirmwarePatternStream: Sendable {

    /// One scheduled command.
    public struct Event: Sendable {
        public var timeMs: Double
        /// 0 = Color0, 1 = Color1, 2 = one LED, 3 = all LEDs, 4 = global
        /// off, 5 = fade rate.
        public var kind: Int
        public var a: Int
        public var b: Int
        public var c: Int
    }

    /// The ring state at one instant.
    public struct Frame: Sendable {
        public var color0: Color
        public var color1: Color
        /// Per LED: nil when dark, otherwise the color it is showing.
        public var leds: [Color?]
    }

    public var name: String
    public var totalMs: Double
    public var events: [Event]

    /// How long one pass takes, in seconds.
    public var loopSeconds: Double { max(totalMs / 1000, 0.1) }

    /// The ring state `seconds` into the pattern, wrapping.
    ///
    /// A linear walk from the start each call rather than an incremental
    /// cursor: the caller may scrub backwards, and a timeline can render
    /// any instant in any order, so there is no monotonic playhead to
    /// depend on. At a few hundred events this is cheap — but it is once
    /// per *frame*, never per diode. See `RingView`, which resolves the
    /// frame before the diode loop for exactly that reason.
    public func frame(atSeconds seconds: Double, ledCount: Int = 16) -> Frame {
        let total = max(totalMs, 1)
        var t = (seconds * 1000).truncatingRemainder(dividingBy: total)
        if t < 0 { t += total }

        var color0 = Color.black
        var color1 = Color.black
        var bits = [Int](repeating: 0, count: ledCount)
        var selected = [Bool](repeating: false, count: ledCount)

        for event in events {
            if event.timeMs > t { break }
            switch event.kind {
            case 0: color0 = Self.rgb(event.a, event.b, event.c)
            case 1: color1 = Self.rgb(event.a, event.b, event.c)
            case 2:
                guard event.a >= 0, event.a < ledCount else { continue }
                selected[event.a] = event.b != 0
                bits[event.a] = event.c
            case 3:
                for i in 0..<ledCount {
                    selected[i] = event.a != 0
                    bits[i] = event.b
                }
            case 4:
                for i in 0..<ledCount {
                    selected[i] = false
                    bits[i] = 0
                }
            default:
                // Fade rate: a hardware ramp between states with no
                // equivalent in a per-frame snapshot. Recorded so the
                // stream stays complete, ignored when drawing.
                break
            }
        }

        let leds = (0..<ledCount).map { i -> Color? in
            guard selected[i] else { return nil }
            return bits[i] == 0 ? color0 : color1
        }
        return Frame(color0: color0, color1: color1, leds: leds)
    }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    // MARK: - Library

    /// Every recorded pattern, by module name. Decoded once.
    public static let library: [String: FirmwarePatternStream] = loadLibrary()

    public static func stream(named name: String) -> FirmwarePatternStream? {
        library[name]
    }

    private struct Raw: Decodable {
        let total_ms: Double
        let events: [[Double]]
    }

    private static func loadLibrary() -> [String: FirmwarePatternStream] {
        guard let url = Bundle.module.url(forResource: "firmware-streams", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: Raw].self, from: data) else {
            return [:]
        }
        return raw.reduce(into: [:]) { result, entry in
            let events = entry.value.events.compactMap { row -> Event? in
                guard row.count >= 5 else { return nil }
                return Event(
                    timeMs: row[0],
                    kind: Int(row[1]),
                    a: Int(row[2]),
                    b: Int(row[3]),
                    c: Int(row[4])
                )
            }
            result[entry.key] = FirmwarePatternStream(
                name: entry.key,
                totalMs: entry.value.total_ms,
                events: events
            )
        }
    }
}
