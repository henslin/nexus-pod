import SwiftUI

/// Reads a hand-written Blender LED-ring script and interprets as much of it
/// as this app can actually represent.
///
/// Distinct from `CodeGenerators.applyBlenderCode`, which round-trips *this
/// app's own* export by reading its `NEXUS_PARAMS` block. That one is exact
/// and fails cleanly on anything else. This one is for foreign scripts —
/// someone else's ring animation, written against their own scene — where
/// there is no agreed format and an exact reproduction isn't possible.
///
/// So this is deliberately an **interpretation, not a translation**, and it
/// reports itself as one. The result carries what was understood *and* what
/// was recognized-but-dropped, because the failure mode that matters here
/// isn't refusing a file — it's silently importing half of one and leaving
/// someone to wonder why the ring doesn't match their render.
///
/// The parsing itself is intentionally dumb: module-level `NAME = value`
/// assignments, uppercase only, numbers and 3-tuples. That covers the
/// "tunable knobs at the top of the file" convention these scripts follow
/// without pretending to execute Python.
public enum BlenderScriptImporter {

    public struct Outcome {
        /// Human-readable lines describing what was set, e.g.
        /// "16 LEDs → Diode Count, Diode Mode on".
        public var applied: [String]
        /// Constants that were found and understood as meaningful, but have
        /// no equivalent here — the honest part of the report.
        public var dropped: [String]
        /// Set when the mapping is an approximation rather than a match.
        public var caveat: String?

        public var isEmpty: Bool { applied.isEmpty }

        public init(applied: [String], dropped: [String], caveat: String?) {
            self.applied = applied
            self.dropped = dropped
            self.caveat = caveat
        }
    }

    /// Parsed value of one module-level constant.
    private enum Value {
        case number(Double)
        case triple(Double, Double, Double)
    }

    public static func apply(_ text: String, to config: RingConfig) -> Outcome {
        let constants = parseConstants(text)
        var applied: [String] = []
        var dropped: [String] = []
        var caveat: String?

        // --- LED count. The strongest signal that this is a physical ring
        // --- script rather than a continuous-arc one, so it also turns on
        // --- Diode Mode: these scripts drive N fixed pixels by brightness,
        // --- which is exactly what that mode renders.
        var ledCount: Double?
        for key in ["NUM_LEDS", "N_LEDS", "LED_COUNT", "NUM_PIXELS"] {
            if case .number(let n) = constants[key] ?? .number(.nan), n.isFinite, n >= 2 {
                ledCount = n
                config.diodeCount = min(max(n, 8), 60)
                config.diodeModeEnabled = true
                applied.append("\(Int(n)) LEDs → Diode Count, Diode Mode on")
                break
            }
        }

        // --- Style. Honors what the script says it is rather than guessing
        // --- from the maths: `STYLE_Ripple`, a `STYLE = "..."`, or a bare
        // --- mention of a type name in the header comment.
        if let type = detectAnimationType(in: text) {
            config.animationType = type
            applied.append("Style reads as \(type.rawValue) → Animation Type")
            if type == .ripple {
                // Kept honest as the app caught up: this used to say Ripple
                // had no multi-drop equivalent at all. It does now — drops,
                // decay, lifetime, seed, loop and seam-wrapping all
                // transfer — so what's left is the scene-side shading a
                // renderer does and a ring driver doesn't.
                caveat = """
                    Drops, decay, lifetime, seed and loop length all transfer, \
                    and overlapping fronts add together the same way. What \
                    doesn't: the script's luminance compensation and scene \
                    emission boosts, which shape brightness per frame in \
                    Blender's renderer, and its hue-ramp crossover — the ramp \
                    here is linear across your palette rather than weighted \
                    toward the hot core.
                    """
            }
        }

        // --- Floor / base glow. Bloom's base brightness is the same idea:
        // --- the level the ring never drops below.
        for key in ["FLOOR", "FLOOR_LEVEL", "BASE_GLOW", "MIN_LEVEL"] {
            if case .number(let n) = constants[key] ?? .number(.nan), n.isFinite {
                // Both: `diodeFloor` is the global one these scripts mean,
                // `bloomBase` is Bloom's own, so the value is right either
                // way the file is interpreted.
                config.diodeFloor = min(max(n, 0), 1)
                config.bloomBase = min(max(n, 0), 1)
                applied.append(String(format: "Floor %.2f → Floor / Base Brightness", n))
                break
            }
        }

        // --- Speed. These scripts express it in ring positions per second;
        // --- `RingConfig.speed` is laps per second, so it needs the LED
        // --- count to convert. Without that there's nothing to divide by,
        // --- and a raw 5.5 would be a wild over-read.
        for key in ["RIPPLE_SPEED", "SPEED", "TRAVEL_SPEED", "WAVE_SPEED"] {
            if case .number(let n) = constants[key] ?? .number(.nan), n.isFinite, n > 0 {
                if let leds = ledCount {
                    let laps = n / leds
                    config.speed = min(max(laps, 0.1), 3.0)
                    applied.append(String(format: "%.1f positions/s over %d LEDs → %.2fx speed", n, Int(leds), laps))
                } else {
                    dropped.append("\(key) (no LED count to convert positions/second into laps/second)")
                }
                break
            }
        }

        // --- Front thickness, in LED units — same conversion problem.
        for key in ["PULSE_W", "PULSE_WIDTH", "WIDTH", "SIGMA"] {
            if case .number(let n) = constants[key] ?? .number(.nan), n.isFinite, n > 0, let leds = ledCount {
                let fraction = min(max(n / leds, 0.05), 1.0)
                config.trailFraction = fraction
                applied.append(String(format: "Front width %.1f LEDs → %.2f of the ring", n, fraction))
                break
            }
        }

        // --- Drop count. Feeds both models: Ripple's drops (which is what
        // --- these scripts mean) and Bloom's patches, so the number is
        // --- right whichever type the file turns out to be.
        for key in ["N_DROPS", "DROPS", "N_PATCHES", "NUM_DROPS"] {
            if case .number(let n) = constants[key] ?? .number(.nan), n.isFinite, n >= 1 {
                config.rippleDropCount = min(max(n, 1), 12)
                config.bloomCount = min(max(n, 2), 14)
                applied.append("\(Int(n)) drops → Drops / Patches")
                break
            }
        }

        // --- Ripple shaping. These were reported as dropped until the app
        // --- grew somewhere to put them.
        if case .number(let decay) = constants["DECAY_RATE"] ?? .number(.nan), decay.isFinite, decay >= 0 {
            config.rippleDecay = min(decay, 2)
            applied.append(String(format: "Decay %.2f/s → Decay", decay))
        }
        if case .number(let life) = constants["RIPPLE_LIFE"] ?? .number(.nan), life.isFinite, life > 0 {
            config.rippleLife = min(max(life, 0.5), 12)
            applied.append(String(format: "Drop life %.1fs → Drop Life", life))
        }
        if case .number(let seed) = constants["SEED"] ?? .number(.nan), seed.isFinite {
            config.rippleSeed = min(max(seed.rounded(), 0), 999)
            applied.append("Seed \(Int(seed)) → Seed")
        }

        // --- Palette. sRGB 0-255 triples, in file order: primary, secondary,
        // --- then any extras become additional colors — the same list the
        // --- Color section builds.
        let palette = paletteTriples(constants, text: text)
        if !palette.isEmpty {
            config.primaryColor = palette[0]
            if palette.count > 1 { config.secondaryColor = palette[1] }
            if palette.count > 2 { config.additionalColors = Array(palette.dropFirst(2)) }
            applied.append("\(palette.count) palette color\(palette.count == 1 ? "" : "s") → Color section")
        }

        // --- Brightness-driven color. A script with a level→hue ramp is
        // --- describing exactly what `DiodeColorMode.byLevel` does, and
        // --- the app can't express it any other way, so it's worth
        // --- detecting rather than dropping the palette into per-diode
        // --- slots where it would read as unrelated colored pixels.
        let lowered = text.lowercased()
        let ramps = lowered.contains("colcurve")
            || lowered.contains("hue ramp")
            || lowered.contains("color ramp")
            || lowered.contains("strength effect, not a")
        if ramps, palette.count > 1 {
            config.diodeColorMode = .byLevel
            var note = "Level→hue ramp → Diode Color: By Brightness"

            // A ramp that tops out at white usually says so in constants
            // the tuple scraper can't see (`_WHITE = [1.0, 1.0, 1.0]` is a
            // list, and often built rather than declared). Append it so the
            // hot core exists, since that's the end of the ramp the script
            // is describing.
            if lowered.contains("white") && config.additionalColors.count < 2 {
                config.additionalColors.append(.white)
                note += ", white added as the hot core"
            }
            applied.append(note)
        }

        // --- Things worth naming as understood-but-unrepresentable, so the
        // --- report explains a mismatch instead of leaving it a mystery.
        for (key, label) in [
            ("WHITE_START", "hue-ramp crossover point"),
            ("EMISSION_BOOST", "scene emission boost"),
            ("GREEN_BOOST", "scene green boost")
        ] where constants[key] != nil {
            dropped.append("\(key) — \(label)")
        }

        // Loop length is informational: the app has no single "this animation
        // lasts N seconds" knob outside a timeline, so say so rather than
        // pretending to apply it.
        if case .number(let frames) = constants["LOOP_FRAMES"] ?? .number(.nan),
           case .number(let fps) = constants["FPS"] ?? .number(.nan),
           frames.isFinite, fps > 0 {
            let seconds = frames / fps
            config.loopSeconds = min(max(seconds, 1), 30)
            applied.append(String(format: "%.0f frames @ %.0f fps → %.1fs Loop Length", frames, fps, seconds))
        }

        // --- Firmware tick. Scripts that quantize to a hardware tick say so
        // --- in a constant or in the header; either is worth honoring,
        // --- because rendering smoother than the device can update is
        // --- exactly the kind of flattery this is meant to avoid.
        for key in ["TICK_MS", "FIRMWARE_TICK_MS", "TICK"] {
            if case .number(let n) = constants[key] ?? .number(.nan), n.isFinite, n > 0 {
                config.firmwareTickMs = min(n, 200)
                applied.append(String(format: "%.0f ms tick → Firmware Tick", n))
                break
            }
        }
        if config.firmwareTickMs == 0, let tick = tickFromProse(text) {
            config.firmwareTickMs = tick
            applied.append(String(format: "%.0f ms tick, read from the header → Firmware Tick", tick))
        }

        return Outcome(applied: applied, dropped: dropped, caveat: caveat)
    }

    // MARK: - Parsing

    /// Module-level `NAME = value` assignments, uppercase names only.
    ///
    /// Uppercase because that's the convention these scripts use for their
    /// tunable block, and it keeps the scraper away from ordinary locals
    /// inside functions — which a line-based reader would otherwise happily
    /// pick up and misread.
    private static func parseConstants(_ text: String) -> [String: Value] {
        var result: [String: Value] = [:]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
            // Indented lines are inside a def/class, not module-level knobs.
            guard !line.hasPrefix(" "), !line.hasPrefix("\t") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name == name.uppercased(),
                  name.allSatisfy({ $0.isUppercase || $0.isNumber || $0 == "_" }),
                  let first = name.first, first.isUppercase else { continue }
            let raw = parts[1].trimmingCharacters(in: .whitespaces)
            if let value = parseValue(raw) { result[name] = value }
        }
        return result
    }

    private static func parseValue(_ raw: String) -> Value? {
        if let number = Double(raw) { return .number(number) }
        guard raw.hasPrefix("("), raw.hasSuffix(")") else { return nil }
        let inner = raw.dropFirst().dropLast()
        let pieces = inner.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard pieces.count == 3 else { return nil }
        return .triple(pieces[0], pieces[1], pieces[2])
    }

    /// Colors, in the order they appear in the file.
    ///
    /// Ordered by position in the source rather than by dictionary iteration,
    /// which is unordered — otherwise "primary" would be whichever color the
    /// hash happened to yield first, and would change between runs.
    private static func paletteTriples(_ constants: [String: Value], text: String) -> [Color] {
        let names = constants.compactMap { key, value -> String? in
            guard case .triple = value else { return nil }
            return key
        }
        let ordered = names.sorted { lhs, rhs in
            (text.range(of: lhs)?.lowerBound ?? text.startIndex) < (text.range(of: rhs)?.lowerBound ?? text.startIndex)
        }
        return ordered.compactMap { name in
            guard case .triple(let r, let g, let b) = constants[name] else { return nil }
            // 0-255 is the overwhelmingly common convention in these files;
            // anything at or below 1 is treated as already normalized.
            let scale = (r > 1 || g > 1 || b > 1) ? 255.0 : 1.0
            return Color(
                red: min(max(r / scale, 0), 1),
                green: min(max(g / scale, 0), 1),
                blue: min(max(b / scale, 0), 1)
            )
        }
    }

    /// A firmware tick stated in prose rather than a constant, e.g.
    /// "50 ms tick" or "quantized to 100 ms".
    ///
    /// Worth the scrape because these scripts routinely bake the tick into
    /// a comment and only expose the *keying* interval as a constant — the
    /// tick itself is the hardware fact, and it's the one that matters for
    /// an honest preview.
    private static func tickFromProse(_ text: String) -> Double? {
        let lowered = text.lowercased()
        guard lowered.contains("tick") else { return nil }
        let pattern = #"(\d{1,3})\s*ms"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(lowered.startIndex..., in: lowered)
        var best: Double?
        regex.enumerateMatches(in: lowered, range: range) { match, _, _ in
            guard let match, let r = Range(match.range(at: 1), in: lowered),
                  let value = Double(lowered[r]), value > 0, value <= 200 else { return }
            // Smallest plausible figure: the tick is the base rate, and
            // keying intervals quoted alongside it are multiples of it.
            best = min(best ?? value, value)
        }
        return best
    }

    /// The animation type the script says it is.
    ///
    /// Matches on `RingAnimationType`'s own display names so it stays correct
    /// as types are added — a script naming a type this app doesn't have
    /// simply doesn't match, and the import proceeds without setting one.
    private static func detectAnimationType(in text: String) -> RingAnimationType? {
        let haystack = text.lowercased()
        // Longest names first: "Dual Chase" must win over "Chase" would-be
        // substrings, and "Multi Chase" over "Chase".
        let candidates = RingAnimationType.allCases.sorted { $0.rawValue.count > $1.rawValue.count }
        for type in candidates {
            let needle = type.rawValue.lowercased()
            if haystack.contains("style_\(needle.replacingOccurrences(of: " ", with: "_"))")
                || haystack.contains("style_\(needle.replacingOccurrences(of: " ", with: ""))")
                || haystack.contains("style = \"\(needle)\"")
                || haystack.contains("style_\(needle)") {
                return type
            }
        }
        return nil
    }
}
