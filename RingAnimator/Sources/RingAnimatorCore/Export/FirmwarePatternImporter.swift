import SwiftUI

/// Reads a *firmware pattern module* — one file out of the `patterns/`
/// library that drives the physical ring — and interprets it into a
/// `RingConfig`.
///
/// This is the second of the two foreign-script readers, and it exists
/// because the first one couldn't see these files at all.
/// `BlenderScriptImporter` scrapes module-level UPPERCASE `NAME = value`
/// knobs, which is the right shape for a standalone Blender scene script
/// (`ripple.py` and friends). A firmware pattern module is built the other
/// way round: it imports its constants and its maths from a shared
/// `pattern_common`, keeps almost nothing at module level, and puts every
/// tunable *inside* the `schedule_*` function as an ordinary lowercase
/// local. Pointed at one of those, the uppercase scraper found nothing and
/// reported "nothing to import", which reads as a broken importer rather
/// than a mismatched one.
///
/// What these files do expose, reliably, is three things:
///
/// 1. **Which shared helper they delegate to.** `_schedule_wake_bloom`,
///    `_schedule_braided_twist`, `_schedule_level_threshold` and the rest
///    are a small, closed vocabulary of ring behaviors, and the helper name
///    is a far better statement of intent than anything inferable from the
///    body. That's the primary signal.
/// 2. **Their palette**, as inline `(r, g, b)` tuples in the call arguments
///    or as named constants like `COLOR_AMBER`.
/// 3. **Their timing**, as `DURATION_MS` at module level and `loop_seconds`
///    / `rotation_ms` / `tick_ms` inside the body.
///
/// The ~25 files with hand-written bodies rather than a helper call give up
/// even more: `color0_rgb`, `color1_rgb`, `brightness_min`, `seed`,
/// `loop_seconds` and `fade_rate_idx` are the same concepts this app
/// already models, under different names.
///
/// ## What this deliberately does not claim
///
/// `pattern_common.py` and `led_ring_patterns.py` are imported by every one
/// of these files and are **not** in the folder. The actual per-LED maths
/// therefore isn't available to read, so a helper name is mapped to *this
/// app's nearest behavior* rather than reproduced. Likewise the named
/// colors resolve to this app's own spec palette (`LEDCueColors`), not to
/// whatever RGB `pattern_common` defines. Both substitutions are stated in
/// the report rather than glossed, for the same reason the other importer
/// states its own: importing half a file silently is worse than importing
/// none of it loudly.
public enum FirmwarePatternImporter {

    /// True when the text is a firmware pattern module rather than a
    /// freestanding scene script.
    ///
    /// The `pattern_common` import is the unambiguous tell — every file in
    /// the library has it and nothing else does. The second clause catches
    /// a module that's been copied out of the package and had its imports
    /// stripped, which still parses fine here.
    public static func matches(_ text: String) -> Bool {
        if text.contains("pattern_common") { return true }
        return text.contains("DESCRIPTION") && text.contains("def schedule_")
    }

    /// One entry in the closed vocabulary of shared schedulers.
    private struct Behavior {
        var type: RingAnimationType?
        var style: LEDPatternStyle?
        /// Whether the behavior addresses fixed pixels by brightness (as
        /// opposed to drawing a continuous arc). Drives Diode Mode.
        var diode: Bool = true
        /// Color comes from level rather than from position — the
        /// one-color-at-two-brightnesses shape the firmware uses.
        var byLevel: Bool = false
        var note: String
    }

    /// Helper name → nearest behavior this app can render.
    ///
    /// Ordered longest-first at the point of use so `_schedule_spin_solid_fade`
    /// can't be matched by `_schedule_spin_firmware`'s shorter prefix.
    private static let behaviors: [String: Behavior] = [
        "_schedule_solid_firmware": Behavior(
            type: nil, style: .solid,
            note: "steady unblinking color"),
        "_schedule_spin_firmware": Behavior(
            type: nil, style: .spin,
            note: "single arc travelling the ring"),
        "_schedule_spin_solid_fade": Behavior(
            type: nil, style: .spinThenSolidFade,
            note: "spin resolving into a solid fade"),
        "_schedule_blink_cycle": Behavior(
            type: nil, style: .flash,
            note: "on/off blink cycle"),
        "_schedule_alternating_firmware": Behavior(
            type: .alternating, style: nil,
            note: "even/odd diodes swapping"),
        "_schedule_white_breath": Behavior(
            type: .pulse, style: nil,
            note: "whole-ring breath"),
        "_schedule_wake_bloom": Behavior(
            type: .bloom, style: nil,
            note: "soft zones surfacing and receding"),
        "_schedule_warble_kaleidoscope": Behavior(
            type: .wobble, style: nil,
            note: "folded warble"),
        "_schedule_connected_flow": Behavior(
            type: .chasing, style: nil,
            note: "flowing arc"),
        "_schedule_battery_cascade": Behavior(
            type: .liquidFill, style: nil, byLevel: true,
            note: "cascading fill to a level"),
        "_schedule_braided_twist": Behavior(
            type: .dualChase, style: nil,
            note: "two counter-rotating arcs"),
        "_dual_comet_varied": Behavior(
            type: .dualChase, style: nil,
            note: "two comets at differing speeds"),
    ]

    /// Helpers that are *rendering primitives* rather than behaviors.
    ///
    /// `_schedule_level_threshold` maps a computed per-LED level onto the
    /// two palette registers; seventeen files call it, and they are a
    /// shimmer, a strobing lattice, a swinging hotspot and so on — not
    /// seventeen liquid fills. It says how the pattern is drawn, not what
    /// it is. `_in_any_arc` is the same: a geometry test, and it co-occurs
    /// with the real signal. Both are consulted only after the module's own
    /// name and description have failed to say anything, so a genuine
    /// "fill to a level" still lands somewhere sensible.
    private static let weakBehaviors: [String: Behavior] = [
        "_schedule_level_threshold": Behavior(
            type: .liquidFill, style: nil, byLevel: true,
            note: "per-LED level mapped onto two colors"),
        "_in_any_arc": Behavior(
            type: .bloom, style: nil,
            note: "lit arcs with gaps between them"),
    ]

    /// Fallbacks for the hand-written bodies, which have no helper call to
    /// key off. Matched against the module name and `DESCRIPTION` prose.
    ///
    /// Longest phrases first so "dual comet" beats "comet".
    private static let keywordBehaviors: [(String, Behavior)] = [
        ("dual comet", Behavior(type: .dualChase, style: nil, note: "two comets")),
        ("dual color", Behavior(type: .dualChase, style: nil, note: "two colors chasing")),
        ("circular fill", Behavior(type: .liquidFill, style: nil, byLevel: true, note: "progress fill")),
        ("alternating", Behavior(type: .alternating, style: nil, note: "two colors swapping")),
        ("kaleidoscope", Behavior(type: .wobble, style: nil, note: "folded warble")),
        ("interference", Behavior(type: .aurora, style: nil, note: "interfering soft fields")),
        ("voiceprint", Behavior(type: .sparkle, style: nil, note: "per-diode hashed shimmer")),
        ("automaton", Behavior(type: .sparkle, style: nil, note: "cell states toggling")),
        ("pendulum", Behavior(type: .wobble, style: nil, note: "a hotspot swinging back and forth")),
        ("waveform", Behavior(type: .equalizer, style: nil, byLevel: true, note: "level bars")),
        ("spotlight", Behavior(type: .chasing, style: nil, note: "a bright arc sweeping")),
        ("cascade", Behavior(type: .liquidFill, style: nil, byLevel: true, note: "cascading fill")),
        ("shimmer", Behavior(type: .sparkle, style: nil, note: "twinkling diodes")),
        ("flicker", Behavior(type: .sparkle, style: nil, note: "twinkling diodes")),
        ("sparkle", Behavior(type: .sparkle, style: nil, note: "twinkling diodes")),
        ("lattice", Behavior(type: .pulse, style: nil, note: "phase-spread pulsing points")),
        ("offline", Behavior(type: .alternating, style: nil, note: "two colors swapping")),
        ("rainbow", Behavior(type: .chasing, style: nil, note: "hue sweep around the ring")),
        ("perlin", Behavior(type: .aurora, style: nil, note: "noise-driven drift")),
        ("plasma", Behavior(type: .aurora, style: nil, note: "noise-driven drift")),
        ("aurora", Behavior(type: .aurora, style: nil, note: "drifting soft fields")),
        ("ripple", Behavior(type: .ripple, style: nil, byLevel: true, note: "expanding drops")),
        ("ribbon", Behavior(type: .chasing, style: nil, note: "a travelling band")),
        ("failed", Behavior(type: .alternating, style: nil, note: "two colors swapping")),
        ("bubble", Behavior(type: .bloom, style: nil, note: "zones surfacing")),
        ("breath", Behavior(type: .pulse, style: nil, note: "whole-ring breath")),
        ("strobe", Behavior(type: nil, style: .quickFlash, note: "hard on/off")),
        ("alarm", Behavior(type: nil, style: .flash, note: "urgent blink")),
        ("bloom", Behavior(type: .bloom, style: nil, note: "zones surfacing")),
        ("comet", Behavior(type: .chasing, style: nil, note: "an arc with a trail")),
        ("drift", Behavior(type: .aurora, style: nil, note: "slow drift")),
        ("swarm", Behavior(type: .sparkle, style: nil, note: "scattered motion")),
        ("flock", Behavior(type: .sparkle, style: nil, note: "scattered motion")),
        ("twist", Behavior(type: .dualChase, style: nil, note: "two counter-rotating arcs")),
        ("blink", Behavior(type: nil, style: .flash, note: "on/off blink")),
        ("pulse", Behavior(type: .pulse, style: nil, note: "whole-ring pulse")),
        ("swing", Behavior(type: .wobble, style: nil, note: "back-and-forth swing")),
        ("solid", Behavior(type: nil, style: .solid, note: "steady color")),
        ("gaps", Behavior(type: .bloom, style: nil, note: "dark gaps travelling a lit ring")),
        ("spin", Behavior(type: nil, style: .spin, note: "an arc travelling the ring")),
        ("wave", Behavior(type: .wave, style: nil, note: "travelling wave")),
        ("load", Behavior(type: .chasing, style: nil, note: "a progress arc")),
        ("sos", Behavior(type: nil, style: .flash, note: "urgent blink")),
    ]

    /// Named palette constants, which live in the absent `pattern_common`.
    /// Resolved to this app's own spec palette — see the type's doc comment
    /// for why that substitution is reported rather than hidden.
    private static let namedColors: [String: Color] = [
        "COLOR_WHITE": rgb(255, 255, 255),
        "COLOR_GREEN": rgb(48, 209, 88),
        "COLOR_RED": rgb(255, 59, 48),
        "COLOR_AMBER": rgb(255, 176, 0),
        "COLOR_BLUE": rgb(10, 132, 255),
        "COLOR_PURPLE": rgb(175, 82, 222),
        "COLOR_ALARM": rgb(255, 59, 48),
        "ARM_RED": rgb(255, 59, 48),
        "ARM_AWAY_RED": rgb(255, 59, 48),
        "ARM_HOME_AMBER": rgb(255, 176, 0),
        "STANDBY_GREEN": rgb(48, 209, 88),
    ]

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r / 255, green: g / 255, blue: b / 255)
    }

    // MARK: - Entry point

    public static func apply(_ text: String, to config: RingConfig) -> BlenderScriptImporter.Outcome {
        var applied: [String] = []
        var dropped: [String] = []

        let description = self.description(in: text)
        let locals = self.locals(in: text)

        // --- Behavior. The helper call if there is one, prose keywords if
        // --- there isn't. Longest helper name first so a name that is a
        // --- prefix of another can't win by appearing earlier in the file.
        // Resolution order, strongest statement of intent first:
        //
        //   1. A named behavior helper — the file saying outright what it is.
        //   2. The module's own name, which these files keep descriptive
        //      and specific (`traveling_ribbon`, `pendulum_swing_...`).
        //   3. The `DESCRIPTION` prose, which is a sentence about the
        //      pattern and so mentions incidental things the name doesn't.
        //   4. A rendering primitive — see `weakBehaviors`.
        //
        // The name has to beat the prose: `spinning_rainbow_quad` describes
        // itself in a way that mentions ripples, and read prose-first it
        // imported as a Ripple. Its name says rainbow, and its name is right.
        var behavior: Behavior?
        var source = ""

        for name in behaviors.keys.sorted(by: { $0.count > $1.count }) where text.contains(name + "(") {
            behavior = behaviors[name]
            source = name
            break
        }

        // Underscores flattened to spaces so a single space-form keyword
        // table matches both `circular_fill` and "circular fill".
        let spacedName = moduleName(in: text).lowercased()
        if behavior == nil {
            for (keyword, candidate) in keywordBehaviors where spacedName.contains(keyword) {
                behavior = candidate
                source = "\"\(keyword)\" in the pattern name"
                break
            }
        }
        if behavior == nil {
            let prose = description.lowercased()
            for (keyword, candidate) in keywordBehaviors where prose.contains(keyword) {
                behavior = candidate
                source = "\"\(keyword)\" in the description"
                break
            }
        }
        if behavior == nil {
            for name in weakBehaviors.keys.sorted(by: { $0.count > $1.count }) where text.contains(name + "(") {
                behavior = weakBehaviors[name]
                source = name
                break
            }
        }

        if let behavior {
            if let style = behavior.style {
                config.patternStyle = style
                config.animationType = .wave
                applied.append("\(source) → \(styleName(style)) (\(behavior.note))")
            } else if let type = behavior.type {
                config.patternStyle = nil
                config.animationType = type
                applied.append("\(source) → \(type.rawValue) (\(behavior.note))")
            }
            if behavior.diode {
                config.diodeModeEnabled = true
                applied.append("Firmware pattern → Diode Mode on")
            }
            if behavior.byLevel {
                config.diodeColorMode = .byLevel
                applied.append("One color at varying brightness → Color by Brightness")
            }
        } else {
            dropped.append("No recognizable scheduler or behavior keyword — animation type left as-is")
        }

        // --- Palette. Call-argument tuples first (most specific), then
        // --- body locals, then named constants.
        var palette = callArgumentColors(in: text)
        if palette.isEmpty { palette = localColors(in: text) }
        var usedNamedColors: [String] = []
        if palette.isEmpty {
            for name in namedColors.keys.sorted(by: { orderOfAppearance($0, text) < orderOfAppearance($1, text) })
            where text.contains(name) {
                if let color = namedColors[name] {
                    palette.append(color)
                    usedNamedColors.append(name)
                }
            }
        }
        if !palette.isEmpty {
            config.primaryColor = palette[0]
            if palette.count > 1 { config.secondaryColor = palette[1] }
            config.additionalColors = palette.count > 2 ? Array(palette.dropFirst(2)) : []
            if usedNamedColors.isEmpty {
                applied.append("\(palette.count) color\(palette.count == 1 ? "" : "s") from the pattern → palette")
            } else {
                applied.append("\(usedNamedColors.joined(separator: ", ")) → palette (this app's spec colors — pattern_common's own RGB values aren't in the folder)")
            }
        }

        // --- Timing.
        if let loop = locals["loop_seconds"], loop > 0 {
            config.loopSeconds = min(max(loop, 0.5), 60)
            applied.append("loop_seconds \(trim(loop)) → Loop Length")
        } else if let ms = durationMS(in: text), ms > 0 {
            config.loopSeconds = min(max(ms / 1000, 0.5), 60)
            applied.append("DURATION_MS \(Int(ms)) → Loop Length \(trim(ms / 1000))s")
        }

        if let rotation = locals["rotation_ms"], rotation > 0 {
            config.speed = min(max(1000 / rotation, 0.05), 5)
            applied.append("rotation_ms \(Int(rotation)) → Speed \(trim(config.speed)) rotations/s")
        }

        // Tick: the hardware's real update rate, which is exactly what
        // Firmware Tick exists to preview. `hue_tick_ms` is the same
        // quantity in the files that key color separately from brightness.
        if let tick = locals["tick_ms"] ?? locals["hue_tick_ms"], tick > 0 {
            config.firmwareTickMs = min(max(tick, 1), 200)
            applied.append("tick \(Int(tick)) ms → Firmware Tick")
        }

        // --- Brightness floor. These patterns are explicit that no LED
        // --- ever goes fully dark; that's the same idea as Diode Floor.
        if let floor = locals["brightness_min"], floor > 0, floor <= 1 {
            config.diodeFloor = floor
            applied.append("brightness_min \(trim(floor)) → Diode Floor")
        }

        if let seed = locals["seed"] {
            config.rippleSeed = seed
            applied.append("seed \(Int(seed)) → Seed")
        }

        if let trail = locals["trail_length"], trail > 0 {
            config.trailFraction = min(max(trail / max(config.diodeCount, 1), 0.02), 1)
            applied.append("trail_length \(Int(trail)) diodes → Trail Length")
        }

        if let cycles = locals["num_cycles"] ?? locals["num_rotations"], cycles >= 1 {
            config.flashCount = Int(min(cycles, 20))
            applied.append("\(Int(cycles)) cycles → Flash Count")
        }

        // --- Recognized but unrepresentable.
        if locals["fade_rate_idx"] != nil || locals["fade_rate"] != nil {
            dropped.append("fade_rate — the hardware's global fade register, which has no per-diode equivalent here")
        }
        for (name, label) in [
            ("zone_scale", "zone_scale — Perlin field scale"),
            ("drift_speed", "drift_speed — Perlin field drift rate"),
            ("white_green_balance", "white_green_balance — the two-color threshold"),
            ("threshold", "threshold — the two-color cutover point"),
            ("start_led", "start_led — starting pixel index"),
        ] where locals[name] != nil {
            dropped.append(label)
        }
        if text.contains("TOTAL_LEDS") {
            dropped.append("TOTAL_LEDS — the ring's pixel count is defined in pattern_common, so Diode Count is unchanged at \(Int(config.diodeCount))")
        }
        if text.contains("RENDER_ONLY = True") {
            dropped.append("RENDER_ONLY — a Blender-render-only flag with no meaning outside that scene")
        }

        let caveat: String
        if applied.isEmpty {
            caveat = "This is a firmware pattern module, but nothing in it mapped onto a behavior this app renders. Its maths lives in pattern_common.py, which isn't in the folder."
        } else {
            caveat = "Interpreted from the pattern's scheduler name, palette and timing. The per-LED maths lives in pattern_common.py, which isn't alongside these files — so this is this app's nearest equivalent behavior, not a frame-exact reproduction."
                + (description.isEmpty ? "" : "\n\nThe pattern describes itself as: \(description)")
        }

        return BlenderScriptImporter.Outcome(applied: applied, dropped: dropped, caveat: caveat)
    }

    // MARK: - Parsing

    /// `DESCRIPTION = ("...")`, including the parenthesized multi-line form
    /// these files use for anything longer than a line.
    private static func description(in text: String) -> String {
        guard let range = text.range(of: "DESCRIPTION") else { return "" }
        let tail = text[range.upperBound...]
        var pieces: [String] = []
        var depth = 0
        var started = false
        for rawLine in tail.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            depth += line.filter { $0 == "(" }.count - line.filter { $0 == ")" }.count
            pieces.append(contentsOf: quotedStrings(in: line))
            if line.contains("(") { started = true }
            if started, depth <= 0 { break }
            if !started, !line.trimmingCharacters(in: .whitespaces).isEmpty { break }
        }
        return pieces.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    private static func quotedStrings(in line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inside = false
        for character in line {
            if character == "\"" {
                if inside { result.append(current); current = "" }
                inside.toggle()
            } else if inside {
                current.append(character)
            }
        }
        return result
    }

    /// The module's own name, taken from the `def schedule_<name>` it
    /// defines — a more reliable label than the file name, which the
    /// importer isn't handed.
    private static func moduleName(in text: String) -> String {
        guard let range = text.range(of: "def schedule_") else { return "" }
        let tail = text[range.upperBound...]
        return String(tail.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
            .replacingOccurrences(of: "_", with: " ")
    }

    /// `DURATION_MS`, tolerating the simple `a * b` product one file uses.
    private static func durationMS(in text: String) -> Double? {
        guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix("DURATION_MS") }) else { return nil }
        let raw = line.split(separator: "=", maxSplits: 1).last.map {
            $0.split(separator: "#", maxSplits: 1)[0].trimmingCharacters(in: .whitespaces)
        } ?? ""
        if let value = Double(raw) { return value }
        let factors = raw.split(separator: "*").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard factors.count >= 2 else { return nil }
        return factors.reduce(1, *)
    }

    /// Indented `name = <number>` assignments inside the scheduler body.
    ///
    /// Whitelisted by name rather than scraped wholesale. These bodies also
    /// contain loop state — `t_ms = 0`, `last_c0 = ...`, `current_time_ms` —
    /// which looks identical to a tunable to a line-based reader and would
    /// be read as one. Only names that are genuinely parameters are taken,
    /// and only their *first* occurrence, since a loop reassigns its
    /// counters further down.
    private static let knownLocals: Set<String> = [
        "loop_seconds", "rotation_ms", "tick_ms", "hue_tick_ms", "seed",
        "brightness_min", "trail_length", "num_cycles", "num_rotations",
        "fade_rate_idx", "fade_rate", "zone_scale", "drift_speed",
        "white_green_balance", "threshold", "start_led",
    ]

    private static func locals(in text: String) -> [String: Double] {
        var result: [String: Double] = [:]
        for rawLine in text.split(separator: "\n") {
            guard rawLine.hasPrefix(" ") || rawLine.hasPrefix("\t") else { continue }
            let line = rawLine.split(separator: "#", maxSplits: 1)[0]
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            guard knownLocals.contains(name), result[name] == nil else { continue }
            if let value = Double(parts[1].trimmingCharacters(in: .whitespaces)) {
                result[name] = value
            }
        }
        return result
    }

    /// `color0_rgb` / `color1_rgb` / `white_rgb` tuples in the body, in
    /// name order — `color0` is the base and `color1` the highlight, which
    /// is the order the firmware's two palette registers are written in.
    private static func localColors(in text: String) -> [Color] {
        var found: [(String, Color)] = []
        for rawLine in text.split(separator: "\n") {
            guard rawLine.hasPrefix(" ") || rawLine.hasPrefix("\t") else { continue }
            let line = rawLine.split(separator: "#", maxSplits: 1)[0]
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            guard name.hasSuffix("_rgb"), !found.contains(where: { $0.0 == name }) else { continue }
            if let color = tuple(String(parts[1].trimmingCharacters(in: .whitespaces))) {
                found.append((name, color))
            }
        }
        return found.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// Inline `(r, g, b)` tuples passed to the scheduler call.
    ///
    /// Scoped to one call's own argument list rather than the whole file so
    /// an unrelated tuple elsewhere in the body can't be read as a palette
    /// entry.
    ///
    /// Every candidate is tried, not just the first: `(controller, system`
    /// also matches the module's own `def schedule_x(controller, system):`,
    /// which always appears above the delegating call and never carries a
    /// palette. Stopping at the first match found that definition, scanned
    /// its empty argument list, and returned no colors — so the patterns
    /// that state their palette most plainly were the ones importing
    /// without one.
    private static func callArgumentColors(in text: String) -> [Color] {
        var searchFrom = text.startIndex
        while let start = text.range(of: "(controller, system", range: searchFrom..<text.endIndex) {
            var depth = 0
            var arguments = ""
            for character in text[start.lowerBound...] {
                if character == "(" { depth += 1 }
                if character == ")" {
                    depth -= 1
                    if depth == 0 { break }
                }
                arguments.append(character)
            }

            var colors: [Color] = []
            var buffer = ""
            var inner = 0
            for character in arguments.dropFirst() {
                if character == "(" { inner += 1; buffer = "("; continue }
                if inner > 0 {
                    buffer.append(character)
                    if character == ")" {
                        inner -= 1
                        if let color = tuple(buffer) { colors.append(color) }
                        buffer = ""
                    }
                }
            }
            if !colors.isEmpty { return colors }
            searchFrom = start.upperBound
        }
        return []
    }

    private static func tuple(_ raw: String) -> Color? {
        guard raw.hasPrefix("("), raw.hasSuffix(")") else { return nil }
        let pieces = raw.dropFirst().dropLast()
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard pieces.count == 3 else { return nil }
        let scale = pieces.contains(where: { $0 > 1 }) ? 255.0 : 1.0
        return Color(
            red: min(max(pieces[0] / scale, 0), 1),
            green: min(max(pieces[1] / scale, 0), 1),
            blue: min(max(pieces[2] / scale, 0), 1)
        )
    }

    private static func orderOfAppearance(_ needle: String, _ text: String) -> Int {
        guard let range = text.range(of: needle) else { return Int.max }
        return text.distance(from: text.startIndex, to: range.lowerBound)
    }

    private static func styleName(_ style: LEDPatternStyle) -> String {
        switch style {
        case .solid: return "Solid"
        case .flash: return "Flash"
        case .quickFlash: return "Quick Flash"
        case .spin: return "Spin"
        case .spinThenSolidFade: return "Spin then Solid Fade"
        default: return "\(style)"
        }
    }

    private static func trim(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }
}
