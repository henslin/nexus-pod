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
        /// off, 5 = fade rate, 6 = one LED set to an explicit packed RGB.
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
    /// The instants this stream's output actually changes, as absolute times
    /// on the same clock `frame(atSeconds:)` takes, spanning
    /// `[seconds - back, seconds + forward]` and looping as the stream does.
    ///
    /// Exists for `RingView`'s persistence pass, which has to sample the
    /// frames themselves rather than evenly spaced instants behind the
    /// playhead — see `RingView.temporalTaps` for why. `RingConfig.firmwareTickMs`
    /// looks like it should answer this and doesn't: it's 0 for most recorded
    /// patterns (the timing lives in the event timestamps), and where it is
    /// set it's a nominal rate rather than the boundaries this particular
    /// recording actually has.
    ///
    /// The boundary *at or before* `seconds` is always included even when it
    /// falls outside the window. It's the frame the playhead is inside, and
    /// dropping it because the frame happens to be older than the trail is
    /// how a ring that never changes ends up with nothing at full weight.
    public func frameBoundaries(
        around seconds: Double,
        back: Double,
        forward: Double,
        limit: Int = 32
    ) -> [Double] {
        guard !events.isEmpty else { return [] }
        let loop = loopSeconds
        let lo = seconds - max(back, 0)
        let hi = seconds + max(forward, 0)

        var collected: [Double] = []
        // Greatest boundary at or before `seconds`.
        var current: Double?

        // One repetition earlier than the window needs, so a window opening
        // just after a loop point still finds the frame it's inside.
        var repetition = ((lo - loop) / loop).rounded(.down)
        let last = (hi / loop).rounded(.down)
        while repetition <= last {
            let origin = repetition * loop
            for event in events {
                let time = origin + event.timeMs / 1000
                if time > hi { break }
                if time <= seconds { current = time }
                // Events cluster at each boundary — a frame is usually a
                // burst of select_led calls sharing one timestamp — so only
                // the distinct times are boundaries.
                if time >= lo, collected.last != time { collected.append(time) }
            }
            repetition += 1
        }

        if let current, collected.first.map({ $0 > current }) ?? true {
            collected.insert(current, at: 0)
        }
        if collected.count > limit {
            collected.removeFirst(collected.count - limit)
        }
        return collected
    }

    /// The hardware's fade time constants, by the index `set_fade_rate`
    /// carries. Mirrors `pattern_common.FADE_TAU_MS`, which in turn mirrors
    /// the Blender simulator's own table.
    private static let fadeTauMs: [Double] = [31, 63, 125, 250, 500, 1000, 2000, 4000]

    /// What the ring was *told* to show at an instant — selection and
    /// palette registers, with no fade applied.
    ///
    /// This is what `FirmwareFieldCheck` compares against the Python
    /// recording, and it is deliberately not what `frame(atSeconds:)`
    /// returns: the recording captures commands, so commands are what a
    /// port-fidelity check can meaningfully compare. How those commands
    /// turn into light is the fade engine's business, and has its own
    /// check.
    public func commandedFrame(atSeconds seconds: Double, ledCount: Int = 16) -> Frame {
        let state = resolve(atSeconds: seconds, ledCount: ledCount)
        let leds = (0..<ledCount).map { i -> Color? in
            if let color = state.explicit[i] { return Self.color(color) }
            guard state.selected[i] else { return nil }
            return Self.color(state.bits[i] == 0 ? state.color0 : state.color1)
        }
        return Frame(color0: Self.color(state.color0), color1: Self.color(state.color1), leds: leds)
    }

    public func frame(atSeconds seconds: Double, ledCount: Int = 16) -> Frame {
        let state = resolve(atSeconds: seconds, ledCount: ledCount)
        // Half a code value: below this an LED is off as far as anything
        // that can display it is concerned, and saying so keeps "these
        // patterns turn pixels off" true rather than leaving a ring of
        // imperceptible embers lit forever.
        let floor = 0.5 / 255
        let leds = state.emitted.map { component -> Color? in
            guard component.0 > floor || component.1 > floor || component.2 > floor else { return nil }
            return Self.color(component)
        }
        return Frame(color0: Self.color(state.color0), color1: Self.color(state.color1), leds: leds)
    }

    private struct ResolvedState {
        var color0: (Double, Double, Double)
        var color1: (Double, Double, Double)
        var bits: [Int]
        var selected: [Bool]
        var explicit: [(Double, Double, Double)?]
        var emitted: [(Double, Double, Double)]
    }

    private func resolve(atSeconds seconds: Double, ledCount: Int) -> ResolvedState {
        let total = max(totalMs, 1)
        var t = (seconds * 1000).truncatingRemainder(dividingBy: total)
        if t < 0 { t += total }

        var color0 = (0.0, 0.0, 0.0)
        var color1 = (0.0, 0.0, 0.0)
        var bits = [Int](repeating: 0, count: ledCount)
        var selected = [Bool](repeating: false, count: ledCount)
        // The snapshot-native patterns (ripple_green) carry a per-LED
        // brightness field rather than a choice between two palette
        // registers, so their LEDs hold an explicit color with the
        // brightness already folded in — which is what the LED emits.
        var explicit = [(Double, Double, Double)?](repeating: nil, count: ledCount)

        // What each LED is actually emitting, which is not the same as what
        // it was last told to show.
        //
        // The ring holds two color registers, so a pattern with more than
        // two colors on screen at once can only be built out of the fade
        // engine: rewrite Color1 every tick, and let each LED that drops out
        // ramp toward black along a line that preserves its hue, freezing it
        // at whichever color was live when it was deselected. That is how
        // every rainbow in this library works — `spinning_rainbow` walks 120
        // hues, and `listen_rainbow_twin_pulse` says so outright in its
        // docstring.
        //
        // Treating a deselected LED as instantly dark, which is what this
        // did before, throws all of that away: measured on the recorded
        // stream, `spinning_rainbow` showed at most *two* distinct colors at
        // any instant while 120 hues went past.
        var emitted = [(Double, Double, Double)](repeating: (0, 0, 0), count: ledCount)
        var tauMs = Self.fadeTauMs[0]
        var lastEventMs = 0.0

        /// Moves every LED toward what it has been told to show, by however
        /// much `dt` at the current time constant allows. First-order, the
        /// same in both directions — the hardware ramps into a color as well
        /// as out of one.
        func advance(to timeMs: Double) {
            let dt = timeMs - lastEventMs
            lastEventMs = timeMs
            guard dt > 0 else { return }
            let k = 1 - exp(-dt / tauMs)
            for i in 0..<ledCount {
                let target: (Double, Double, Double)
                if let color = explicit[i] {
                    target = color
                } else if selected[i] {
                    target = bits[i] == 0 ? color0 : color1
                } else {
                    target = (0, 0, 0)
                }
                emitted[i].0 += (target.0 - emitted[i].0) * k
                emitted[i].1 += (target.1 - emitted[i].1) * k
                emitted[i].2 += (target.2 - emitted[i].2) * k
            }
        }

        for event in events {
            if event.timeMs > t { break }
            advance(to: event.timeMs)
            switch event.kind {
            case 0: color0 = Self.components(event.a, event.b, event.c)
            case 1: color1 = Self.components(event.a, event.b, event.c)
            case 2:
                guard event.a >= 0, event.a < ledCount else { continue }
                selected[event.a] = event.b != 0
                bits[event.a] = event.c
                explicit[event.a] = nil
            case 3:
                for i in 0..<ledCount {
                    selected[i] = event.a != 0
                    bits[i] = event.b
                    explicit[i] = nil
                }
            case 4:
                for i in 0..<ledCount {
                    selected[i] = false
                    bits[i] = 0
                    explicit[i] = nil
                }
            case 5:
                // The fade rate is global — one ramp speed for the ring.
                let index = min(max(event.a, 0), Self.fadeTauMs.count - 1)
                tauMs = Self.fadeTauMs[index]
            case 6:
                guard event.a >= 0, event.a < ledCount else { continue }
                let color = Self.components(
                    (event.b >> 16) & 0xFF,
                    (event.b >> 8) & 0xFF,
                    event.b & 0xFF
                )
                explicit[event.a] = color
                selected[event.a] = true
                // Set outright rather than ramped: a snapshot pattern's
                // steps already carry the brightness they mean to emit, and
                // ramping between them would smear a sequence that was
                // recorded as the finished picture.
                emitted[event.a] = color
            default:
                break
            }
        }
        advance(to: t)

        return ResolvedState(
            color0: color0, color1: color1, bits: bits,
            selected: selected, explicit: explicit, emitted: emitted
        )
    }

    private static func components(_ r: Int, _ g: Int, _ b: Int) -> (Double, Double, Double) {
        (Double(r) / 255, Double(g) / 255, Double(b) / 255)
    }

    private static func color(_ c: (Double, Double, Double)) -> Color {
        Color(red: c.0, green: c.1, blue: c.2)
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
