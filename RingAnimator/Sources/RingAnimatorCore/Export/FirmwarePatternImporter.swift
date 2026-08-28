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

    /// One entry in the closed vocabulary of shared schedulers, carrying
    /// the helper's own documented defaults.
    ///
    /// These numbers are read out of `pattern_common.py` rather than
    /// guessed: `_schedule_spin_solid_fade` really does turn once per
    /// 2200 ms with a 5-LED trail and a 3 s hold, and its three phases
    /// really do add up to the 9400 ms its callers declare. A file that
    /// overrides one of them in its own body overrides it here too — the
    /// defaults are applied first and the locals land on top.
    private struct Behavior {
        var type: RingAnimationType?
        var style: LEDPatternStyle?
        /// Whether the behavior addresses fixed pixels by brightness (as
        /// opposed to drawing a continuous arc). Drives Diode Mode.
        var diode: Bool = true
        /// Color comes from level rather than from position — the
        /// one-color-at-two-brightnesses shape the firmware uses.
        var byLevel: Bool = false
        /// Rotations per second.
        var speed: Double?
        var loopSeconds: Double?
        /// Trail length as a fraction of the ring, already divided by the
        /// 16 LEDs the helpers count in.
        var trailFraction: Double?
        var tickMs: Double?
        var holdSeconds: Double?
        var fadeOutSeconds: Double?
        var note: String
    }

    /// Helper name → nearest behavior this app can render.
    ///
    /// Ordered longest-first at the point of use so `_schedule_spin_solid_fade`
    /// can't be matched by `_schedule_spin_firmware`'s shorter prefix.
    private static let behaviors: [String: Behavior] = [
        // hold 3000 + off 1000 = the 4000 ms its callers declare; fade_idx 4
        // is MEDIUM, tau 500 ms.
        "_schedule_solid_firmware": Behavior(
            type: nil, style: .solid,
            holdSeconds: 3.0, fadeOutSeconds: 0.5,
            note: "steady color, held 3 s then faded out"),
        // Each frame lights *two* LEDs — cw index k and ccw index 15-k — so
        // despite the name this is a mirrored pair sweeping in opposite
        // directions, which is Dual Chase here, not Spin. 16 frames at the
        // documented 312 ms is one 4.99 s revolution.
        "_schedule_spin_firmware": Behavior(
            type: .dualChase, style: nil,
            speed: 1000.0 / (312.0 * 16.0),
            note: "two mirrored heads sweeping in opposite directions"),
        // 2200 ms per lap is the *requested* rate; the engine snaps each
        // step to the 50 ms firmware tick, and 2200/16 = 137.5 rounds up to
        // 150 ms, so a lap really takes 2400 ms. Its own docstring calls
        // this out. Using the requested figure put every one of these three
        // patterns 0.5 s short of the duration its header declares.
        "_schedule_spin_solid_fade": Behavior(
            type: nil, style: .spinThenSolidFade,
            speed: 1000.0 / 2400.0, trailFraction: 5.0 / 16.0,
            holdSeconds: 3.0, fadeOutSeconds: 1.5,
            note: "a comet twice around, then solid, then fade"),
        "_schedule_blink_cycle": Behavior(
            type: nil, style: .flash,
            note: "on/off blink cycle"),
        "_schedule_alternating_firmware": Behavior(
            type: .alternating, style: nil,
            note: "the whole ring alternating between colors"),
        "_schedule_white_breath": Behavior(
            type: .pulse, style: nil,
            speed: 1000.0 / 4000.0, tickMs: 100,
            note: "whole-ring breath on a raised-cosine envelope"),
        "_schedule_wake_bloom": Behavior(
            type: .bloom, style: nil,
            speed: 0.25, loopSeconds: 8, tickMs: 100,
            note: "a slow global breath with a 3-cycle shimmer over it"),
        "_schedule_warble_kaleidoscope": Behavior(
            type: .wobble, style: nil,
            speed: 0.6, loopSeconds: 10, tickMs: 100,
            note: "four mirrored segments breathing symmetrically"),
        "_schedule_connected_flow": Behavior(
            type: .chasing, style: nil,
            loopSeconds: 17.4, tickMs: 100,
            note: "three phases — breathe, bloom, then hold solid"),
        "_schedule_battery_cascade": Behavior(
            type: .liquidFill, style: nil, byLevel: true,
            note: "a cascade filling to a level, then blinking the last LED"),
        "_schedule_braided_twist": Behavior(
            type: .dualChase, style: nil,
            speed: 0.3, loopSeconds: 10, tickMs: 100,
            note: "two phase-opposed strands crossing"),
        // Same tick quantization as the spin engine: `(3000 // 16) // 50 * 50`
        // is 150 ms per LED, so the requested 3000/3400 ms laps land at
        // 2400 and 3200 ms.
        "_dual_comet_varied": Behavior(
            type: .dualChase, style: nil,
            speed: 1000.0 / 2400.0, loopSeconds: 13, trailFraction: 2.0 / 16.0,
            note: "two comets, 2400 ms and 3200 ms per lap"),
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
            tickMs: 100,
            note: "per-LED level hard-thresholded onto two colors"),
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
        ("fill", Behavior(type: .liquidFill, style: nil, byLevel: true, note: "the ring filling up")),
        ("sos", Behavior(type: nil, style: .flash, note: "urgent blink")),
    ]

    /// The firmware palette, read from `pattern_common.py`.
    ///
    /// These are the actual `RGB_*` macro values the device uses, not
    /// lookalikes: the firmware's green is pure `(0, 255, 0)` and its amber
    /// is `(255, 126, 0)`, both a long way from the app's own spec colors
    /// that stood in for them before `pattern_common` was available.
    ///
    /// Matched with word boundaries so `COLOR_GREEN` can't claim a
    /// `COLOR_GREEN_WHITE`, and `COLOR_RED` can't claim a `COLOR_ALARM_RED`.
    private static let namedColors: [String: Color] = [
        "COLOR_WHITE": rgb(255, 255, 255),
        "COLOR_BLUE": rgb(0, 0, 255),
        "COLOR_GREEN": rgb(0, 255, 0),
        "COLOR_RED": rgb(255, 0, 0),
        "COLOR_AMBER": rgb(255, 126, 0),
        "COLOR_ALARM_RED": rgb(220, 0, 0),
        "COLOR_LIGHT_GREEN": rgb(40, 215, 10),
        "COLOR_GREEN_WHITE": rgb(120, 255, 60),
        "COLOR_BLACK": rgb(0, 0, 0),
        "BREATH_WHITE_RGB": rgb(170, 170, 165),
        "ARM_AWAY_RED": rgb(255, 0, 0),
        "ARM_HOME_AMBER": rgb(255, 126, 0),
        "STANDBY_GREEN": rgb(0, 255, 0),
    ]

    /// The ring is 16 LEDs.
    ///
    /// `TOTAL_LEDS` itself lives in `led_ring_core`, which still isn't in
    /// the folder, but `pattern_common`'s geometry pins it exactly:
    /// `TOP_LEDS = [0, 15]`, `LEFT_HALF = [8...15]`, "opposite" is
    /// `(i + 8) % TOTAL_LEDS`, and there are 8 symmetric pairs.
    private static let ringLEDCount: Double = 16

    /// `FADE_TAU_MS` — the fade engine's time constant per rate index.
    private static let fadeTauMs: [Double] = [31, 63, 125, 250, 500, 1000, 2000, 4000]

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r / 255, green: g / 255, blue: b / 255)
    }

    // MARK: - Entry point

    public static func apply(_ text: String, to config: RingConfig) -> BlenderScriptImporter.Outcome {
        var applied: [String] = []
        var dropped: [String] = []

        // The shared library and the registry are not patterns.
        //
        // `pattern_common.py` sits in the same folder, matches every
        // structural test a pattern module passes, and — read as one —
        // imports as whichever helper it happens to define first. The clean
        // discriminator is definition versus use: the library *defines*
        // `_schedule_*`, and a pattern module only ever calls them.
        if text.contains("def _schedule_") {
            return BlenderScriptImporter.Outcome(
                applied: [],
                dropped: [],
                caveat: "This is pattern_common.py — the shared library the patterns are built from, not a pattern itself. Nothing was changed. Import one of the individual pattern files instead."
            )
        }
        if !text.contains("DESCRIPTION") && !text.contains("def schedule_") {
            return BlenderScriptImporter.Outcome(
                applied: [],
                dropped: [],
                caveat: "This file is part of the pattern package but doesn't define a pattern of its own. Nothing was changed."
            )
        }

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

        var strongHelper: String?
        for name in behaviors.keys.sorted(by: { $0.count > $1.count }) where text.contains(name + "(") {
            behavior = behaviors[name]
            source = name
            strongHelper = name
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

            // The helper's documented defaults. Applied before the file's
            // own locals and keywords, which land on top where present.
            if let speed = behavior.speed {
                config.speed = min(max(speed, 0.05), 5)
                applied.append("\(source) turns at \(trim(speed)) rotations/s → Speed")
            }
            if let loop = behavior.loopSeconds {
                config.loopSeconds = min(max(loop, 0.5), 60)
                applied.append("\(trim(loop)) s loop → Loop Length")
            }
            if let trail = behavior.trailFraction {
                config.trailFraction = min(max(trail, 0.02), 1)
                applied.append("\(Int(trail * ringLEDCount))-LED trail → Trail Length")
            }
            if let tick = behavior.tickMs {
                config.firmwareTickMs = min(max(tick, 1), 200)
                applied.append("\(Int(tick)) ms scheduler tick → Firmware Tick")
            }
            if let hold = behavior.holdSeconds {
                config.holdSeconds = hold
                config.sequencePlaybackEnabled = true
                applied.append("held \(trim(hold)) s → Hold")
            }
            if let fade = behavior.fadeOutSeconds {
                config.fadeOutSeconds = fade
                config.sequencePlaybackEnabled = true
                applied.append("\(trim(fade)) s fade to off → Fade Out")
            }
        } else {
            dropped.append("No recognizable scheduler or behavior keyword — animation type left as-is")
        }

        // --- Ring size. Every one of these patterns addresses the same
        // --- 16-pixel ring, so this is a fact about the hardware rather
        // --- than something read out of the individual file.
        if behavior != nil {
            config.diodeCount = ringLEDCount
            applied.append("16-LED ring → Diode Count")
        }

        // --- The exact field, for the patterns built on the firmware's
        // --- level-threshold engine. This is a reproduction rather than an
        // --- interpretation, so it overrides the behavior chosen above and
        // --- brings the engine's real threshold, loop and tick with it.
        let levelField = levelFields[spacedName]
        if let levelField {
            config.firmwareLevelField = levelField
            config.diodeModeEnabled = true
            config.diodeCount = ringLEDCount
            // The engine picks between two palette registers; it never
            // dims, so color must come from the field and not from level.
            config.diodeColorMode = .perDiode
            config.diodeFloor = 0
            config.firmwareTickMs = levelField.tickMs
            config.loopSeconds = min(max(levelField.loopSeconds, 0.5), 60)
            applied.append("Exact firmware field: \(levelField.displayName) — the device's own level(i, t) maths, not an approximation")
            applied.append("threshold \(trim(levelField.threshold)), \(Int(levelField.tickMs)) ms tick, \(trim(levelField.loopSeconds)) s loop → from the engine")
        }

        // --- Palette. Call-argument tuples first (most specific), then
        // --- body locals, then named constants.
        var palette = callArgumentColors(in: text)
        if palette.isEmpty { palette = localColors(in: text) }
        var usedNamedColors: [String] = []
        if palette.isEmpty {
            let present = namedColors.keys
                .compactMap { name -> (String, Int)? in
                    guard let at = wordOccurrence(name, in: text) else { return nil }
                    return (name, at)
                }
                .sorted { $0.1 < $1.1 }
            for (name, _) in present {
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
                applied.append("\(usedNamedColors.joined(separator: ", ")) → palette (the firmware's own RGB values, from pattern_common)")
            }
        }

        // --- Timing.
        if levelField != nil {
            // The engine's own loop and tick are already in place above and
            // are more authoritative than anything scraped from the body.
        } else if let loop = locals["loop_seconds"], loop > 0 {
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
        if levelField == nil, let tick = locals["tick_ms"] ?? locals["hue_tick_ms"], tick > 0 {
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

        // --- Keyword arguments at the call site, which is where these
        // --- files state their real timings: `on_ms=300, off_ms=300`,
        // --- `interval_ms=500`. More specific than the helper defaults
        // --- above, so they overwrite them.
        let keywords = callKeywords(in: text)
        if let on = keywords["on_ms"], let off = keywords["off_ms"], on + off > 0 {
            config.blinkRate = min(max(1000 / (on + off), 0.1), 20)
            applied.append("\(Int(on))/\(Int(off)) ms blink → \(trim(config.blinkRate)) Hz")
        } else if let interval = keywords["interval_ms"], interval > 0 {
            // Two colors at `interval_ms` each means a full there-and-back
            // cycle takes twice that.
            config.speed = min(max(1000 / (interval * 2), 0.05), 5)
            applied.append("\(Int(interval)) ms per color → \(trim(config.speed)) Hz")
        }
        if let hold = keywords["hold_ms"] {
            config.holdSeconds = hold / 1000
            applied.append("hold_ms \(Int(hold)) → Hold \(trim(hold / 1000)) s")
        }
        if let off = keywords["off_ms"], keywords["on_ms"] == nil {
            // `off_ms=0` on a solid means "stay on" — no fade to black.
            config.fadeOutSeconds = off / 1000
            applied.append(off == 0
                ? "off_ms 0 → stays on, no fade to black"
                : "off_ms \(Int(off)) → Fade Out")
        }

        // A bare number passed to the cascade is how many of the 16 LEDs
        // fill — that's the battery level the pattern is showing.
        var litLEDs: Double?
        if text.contains("_schedule_battery_cascade("), let lit = firstPositionalNumber(in: text) {
            litLEDs = lit
            config.trailFraction = min(max(lit / ringLEDCount, 0.02), 1)
            applied.append("\(Int(lit)) of 16 LEDs lit → \(Int(lit / ringLEDCount * 100))% fill")
        }

        // --- Recognized but unrepresentable.
        //
        // `fade_rate` indexes FADE_TAU_MS — the fade engine's exponential
        // time constant. Now that the table is readable the report can name
        // the actual figure instead of calling it an opaque register, even
        // though there's still nowhere here to put a global fade tau.
        if let idx = locals["fade_rate_idx"] ?? locals["fade_rate"], idx >= 0, Int(idx) < fadeTauMs.count {
            dropped.append("fade_rate \(Int(idx)) — the hardware's global fade, \(Int(fadeTauMs[Int(idx)])) ms time constant; no per-diode equivalent here")
        } else if locals["fade_rate_idx"] != nil || locals["fade_rate"] != nil {
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

        if text.contains("RENDER_ONLY = True") {
            dropped.append("RENDER_ONLY — a Blender-render-only flag with no meaning outside that scene")
        }

        // --- Phases. A sequencing engine becomes timeline steps rather
        // --- than collapsing into whichever phase happened to win.
        var timeline: RingTimeline?
        var phases: [String]?
        if let strongHelper {
            (timeline, phases) = phaseTimeline(
                helper: strongHelper,
                palette: palette,
                keywords: keywords,
                litLEDs: litLEDs
            ).map { ($0.0, $0.1) } ?? (nil, nil)
        }
        if timeline == nil, let (built, names) = customPhaseTimeline(name: spacedName) {
            timeline = built
            phases = names
        }
        if let phases {
            applied.append("\(phases.count) phases → timeline steps: \(phases.joined(separator: ", "))")
        }

        let caveat: String
        if applied.isEmpty {
            caveat = "This is a firmware pattern module, but nothing in it named a behavior this app renders. Nothing was changed."
        } else {
            caveat = levelField != nil
                ? "Frame-exact. This pattern's per-LED level(i, t) function is ported from pattern_common.py and verified against it sample for sample, including the 100 ms tick and the two-color threshold. What you see is what the device renders."
                : "Timings, palette and ring size are the firmware's own, read from pattern_common.py. The per-LED maths isn't reproduced for this one — this app renders its nearest equivalent behavior, so expect a close match in color and cadence rather than a frame-exact one."
                + (description.isEmpty ? "" : "\n\nThe pattern describes itself as: \(description)")
        }

        return BlenderScriptImporter.Outcome(
            applied: applied,
            dropped: dropped,
            caveat: caveat,
            timeline: timeline
        )
    }

    // MARK: - Phases

    /// The phase breakdowns, straight out of `pattern_common`'s own
    /// documentation of each engine.
    ///
    /// Only the engines that genuinely sequence get one. A pattern that
    /// loops a single behavior — a warble, a breath, a braid — is fully
    /// described by its config, and wrapping it in a one-step timeline
    /// would add a document to manage for no gain.
    ///
    /// The durations here are not estimates. Each family's phases sum to
    /// the `DURATION_MS` its own callers declare, which is the check that
    /// they're right: 4.4 + 3.0 + 1.5 = 9.4 s for arm_away, and a battery
    /// cascade's `num_leds x 500 ms` plus 8 blink cycles of 600 ms gives
    /// 6800 / 8800 / 10800 ms for the 25/50/75 files exactly.
    private static func phaseTimeline(
        helper: String,
        palette: [Color],
        keywords: [String: Double],
        litLEDs: Double?
    ) -> (RingTimeline, [String])? {
        let primary = palette.first ?? Color.white
        let secondary = palette.count > 1 ? palette[1] : primary

        switch helper {
        case "_schedule_spin_solid_fade":
            // 1. A single comet clockwise, twice around at 2200 ms a lap.
            //    Authored as `.rotations(2)` rather than 4.4 seconds so
            //    "exactly two laps" survives anyone retuning the speed —
            //    that's what `SegmentLength.rotations` is for.
            // 2. Every LED snaps on together, held 3 s.
            // 3. Everything fades to off, ~250 ms time constant.
            let spin = step("Spin x2", length: .rotations(2)) { c in
                c.patternStyle = .spin
                // The tick-quantized 2400 ms lap, not the requested 2200 —
                // and `.rotations(2)` derives the step's 4.8 s from it.
                c.speed = 1000.0 / 2400.0
                c.trailFraction = 5.0 / 16.0
                c.primaryColor = primary
            }
            // 3.1 s, not 3.0: the engine snaps the ring solid 100 ms after
            // the comet's last frame (`solid_at = spin_end + 100`). That
            // gap belongs to neither phase cleanly, and it goes here rather
            // than on the spin so the spin can stay `.rotations(2)` — the
            // count is the thing worth preserving if anyone retunes the
            // speed. Without it the three phases come to 9.3 s against a
            // declared 9.4 s.
            let solid = step("Solid", length: .seconds(3.1)) { c in
                c.patternStyle = .solid
                c.primaryColor = primary
            }
            let fade = step("Fade out", length: .seconds(1.5), fadeOut: 1.5) { c in
                c.patternStyle = .solid
                c.primaryColor = primary
            }
            return (RingTimeline(segments: [spin, solid, fade], loops: true),
                    ["spin x2 (4.8 s)", "solid (3.1 s)", "fade out (1.5 s)"])

        case "_schedule_connected_flow":
            // A 0.0-12.0  soft white breathing, 3 x 4 s
            // B 12.0-16.0 wake-bloom trio in the accent
            // C 16.0-17.4 solid accent, held
            //
            // The accent is the pattern's own color; the breath is
            // BREATH_WHITE_RGB, a deliberately sub-255 neutral white, and
            // hardcoding it here matches the engine rather than reusing
            // the accent for a phase that isn't in the accent.
            let breathWhite = rgb(170, 170, 165)
            let breathe = step("Breathe", length: .seconds(12)) { c in
                c.animationType = .pulse
                c.speed = 1000.0 / 4000.0
                c.primaryColor = breathWhite
                c.secondaryColor = breathWhite
            }
            let bloom = step("Bloom", length: .seconds(4)) { c in
                c.animationType = .bloom
                c.bloomCount = 3
                c.primaryColor = primary
                c.secondaryColor = secondary
            }
            let connected = step("Connected", length: .seconds(1.4)) { c in
                c.patternStyle = .solid
                c.primaryColor = primary
            }
            return (RingTimeline(segments: [breathe, bloom, connected], loops: true),
                    ["breathe 3 x 4 s", "bloom (4 s)", "solid (1.4 s)"])

        case "_schedule_solid_firmware":
            // hold_ms lit, then off_ms dark. `off_ms = 0` means it simply
            // stays on, which is one behavior and gets no timeline.
            let hold = (keywords["hold_ms"] ?? 3000) / 1000
            let off = (keywords["off_ms"] ?? 1000) / 1000
            guard off > 0 else { return nil }
            let lit = step("Solid", length: .seconds(hold), fadeOut: 0.5) { c in
                c.patternStyle = .solid
                c.primaryColor = primary
            }
            let dark = step("Off", length: .seconds(off)) { c in
                c.patternStyle = .off
            }
            return (RingTimeline(segments: [lit, dark], loops: true),
                    ["solid (\(trim(hold)) s)", "off (\(trim(off)) s)"])

        case "_schedule_battery_cascade":
            // `num_leds` frames at 500 ms fill the ring, then 8 blink
            // cycles at 300/300 toggle the last LED while the rest hold.
            guard let lit = litLEDs, lit >= 1 else { return nil }
            let fillSeconds = lit * 0.5
            let blinkSeconds = 8 * 0.6
            let fill = step("Fill to \(Int(lit))", length: .seconds(fillSeconds)) { c in
                c.animationType = .liquidFill
                c.diodeColorMode = .byLevel
                c.trailFraction = min(max(lit / ringLEDCount, 0.02), 1)
                c.primaryColor = primary
            }
            let blink = step("Blink last LED", length: .seconds(blinkSeconds)) { c in
                c.patternStyle = .flash
                c.blinkRate = 1000.0 / 600.0
                c.flashCount = 8
                c.primaryColor = primary
            }
            return (RingTimeline(segments: [fill, blink], loops: true),
                    ["fill to \(Int(lit)) LEDs (\(trim(fillSeconds)) s)",
                     "8 blink cycles (\(trim(blinkSeconds)) s)"])

        default:
            return nil
        }
    }

    /// Which pattern modules are built on the firmware's level-threshold
    /// engine, and which ported field reproduces each one.
    ///
    /// These twenty-one import *exactly* rather than approximately — see
    /// `FirmwareLevelField`. Keyed on the module's own name because that is
    /// what identifies the specific `level(i, t_s)` closure; the helper name
    /// only says which engine runs it.
    ///
    /// The four warbles, two braids and two wake-blooms share a field and
    /// differ only in palette, which is exactly how the source has it — the
    /// engine is in `pattern_common` and the files pass colors to it.
    private static let levelFields: [String: FirmwareLevelField] = [
        "braided twist green": .braidedTwist,
        "braided twist red": .braidedTwist,
        "cellular automaton green": .cellularAutomaton,
        "flocking drift connection green": .flockingDrift,
        "mic level jitter listening blue": .micLevelJitter,
        "pendulum swing deterrence red": .pendulumSwing,
        "quantum tunneling speaking blue": .quantumTunneling,
        "resonant ping decay occupancy green": .resonantPingDecay,
        "ribbon phase warp red": .ribbonPhaseWarp,
        "speaking response waveform blue": .speakingWaveform,
        "strobe pulsing lattice red": .strobePulsingLattice,
        "tidal modulation loading green": .tidalModulation,
        "utterance loudness envelope blue": .utteranceEnvelope,
        "voiceprint shimmer blue": .voiceprintShimmer,
        "wake bloom trio gaps green": .wakeBloomTrioGaps,
        "wake bloom waiting blue navy cobalt": .wakeBloomWaiting,
        "wake bloom waiting blue steel ice": .wakeBloomWaiting,
        "warble kaleidoscope amber": .warbleKaleidoscope,
        "warble kaleidoscope blue": .warbleKaleidoscope,
        "warble kaleidoscope green": .warbleKaleidoscope,
        "warble kaleidoscope red": .warbleKaleidoscope,
    ]

    /// Phases for the hand-written patterns — the ones that sequence
    /// without delegating to a shared engine.
    ///
    /// Keyed on the module's own name because these files have no helper
    /// call to key off. Every number is transcribed from the body rather
    /// than inferred, and where the file declares a `DURATION_MS` the
    /// phases are checked against it: alarm_sos comes to 7560 ms, battery_100
    /// to 14000, device_offline to 10850 — each one matching its header.
    ///
    /// Colors are transcribed too. These bodies pin their own RGB values
    /// (`white_rgb = (180, 180, 180)`, `deterrence_rgb = (180, 35, 0)`), and
    /// a phase means that specific color, not whichever entry of the
    /// scraped palette happened to sort first.
    private static func customPhaseTimeline(name: String) -> (RingTimeline, [String])? {
        let amber = rgb(255, 126, 0)
        let red = rgb(255, 0, 0)
        let alarmRed = rgb(220, 0, 0)
        let blue = rgb(0, 0, 255)
        let white = rgb(255, 255, 255)

        switch name {
        case "alarm sos":
            // 500 ms lead-in, 4 x {3 flashes at 110/170 + 800 ms gap},
            // 500 ms trail. Exactly the 7560 ms its header declares.
            var steps = [step("Lead-in", length: .seconds(0.5)) { $0.patternStyle = .off }]
            steps += burstCycles(
                cycles: 4, flashes: 3,
                onMs: 110, offMs: 170, gapMs: 800, color: alarmRed
            )
            steps.append(step("Trail-off", length: .seconds(0.5)) { $0.patternStyle = .off })
            return (RingTimeline(segments: steps, loops: true),
                    ["lead-in (0.5 s)", "4 x triple burst + gap (6.56 s)", "trail-off (0.5 s)"])

        case "battery 100":
            // 16 cascade frames at 500 ms, hold 5 s, fade off 1 s = 14000.
            let fill = step("Cascade fill", length: .seconds(8)) { c in
                c.animationType = .liquidFill
                c.diodeColorMode = .byLevel
                c.trailFraction = 1
                c.primaryColor = white
            }
            let hold = step("Hold", length: .seconds(5)) { c in
                c.patternStyle = .solid
                c.primaryColor = white
            }
            let fade = step("Fade off", length: .seconds(1), fadeOut: 1) { c in
                c.patternStyle = .solid
                c.primaryColor = white
            }
            return (RingTimeline(segments: [fill, hold, fade], loops: true),
                    ["cascade fill (8 s)", "hold (5 s)", "fade off (1 s)"])

        case "booting up":
            // One cycle is 3 s white then 3 s off, both on the SLOW fade.
            // The 30 s in the header is this 6 s loop played five times, so
            // the loop is what's modeled and the timeline repeats it.
            let lit = step("White", length: .seconds(3), fadeIn: 1, fadeOut: 1) { c in
                c.patternStyle = .solid
                c.primaryColor = white
            }
            let dark = step("Off", length: .seconds(3)) { $0.patternStyle = .off }
            return (RingTimeline(segments: [lit, dark], loops: true),
                    ["white (3 s)", "off (3 s)", "looped 5x for the header's 30 s"])

        case "device offline":
            // A one-time 350 ms fade to dark, then amber/red alternating at
            // 500/500 filling the rest of the 10850 ms.
            let off = step("Fade off", length: .seconds(0.35), fadeOut: 0.35) { c in
                c.patternStyle = .solid
                c.primaryColor = amber
            }
            let alternating = step("Amber / red", length: .seconds(10.5)) { c in
                c.animationType = .alternating
                c.speed = 1.0
                c.primaryColor = amber
                c.secondaryColor = red
            }
            return (RingTimeline(segments: [off, alternating], loops: true),
                    ["fade off (0.35 s)", "amber/red alternating (10.5 s)"])

        case "spotlight deterrence":
            // The seven phases its docstring names, with `breathe = False`
            // and `alarm = True` as the body sets them:
            //   off 500 | white hold 3500 | crossfade 2500 | steady 4500
            //   | dark break 3500 | 4 alarm cycles 6680 | pad 500  = 21680
            let deterrence = rgb(180, 35, 0)
            let spotWhite = rgb(180, 180, 180)
            var steps = [
                step("Off", length: .seconds(0.5)) { $0.patternStyle = .off },
                step("White spotlight", length: .seconds(3.5), fadeIn: 0.5) { c in
                    c.patternStyle = .solid
                    c.primaryColor = spotWhite
                },
                // The crossfade is white to deterrence, so the step carries
                // both and reads as the transition rather than either end.
                step("Crossfade", length: .seconds(2.5)) { c in
                    c.animationType = .pulse
                    c.speed = 1.0 / 5.0
                    c.primaryColor = spotWhite
                    c.secondaryColor = deterrence
                },
                step("Steady hold", length: .seconds(4.5)) { c in
                    c.patternStyle = .solid
                    c.primaryColor = deterrence
                },
                step("Dark break", length: .seconds(3.5)) { $0.patternStyle = .off },
            ]
            steps += burstCycles(
                cycles: 4, flashes: 3,
                onMs: 110, offMs: 180, gapMs: 800, color: alarmRed
            )
            steps.append(step("Off", length: .seconds(0.5)) { $0.patternStyle = .off })
            return (RingTimeline(segments: steps, loops: true),
                    ["off (0.5 s)", "white spotlight (3.5 s)", "crossfade (2.5 s)",
                     "steady hold (4.5 s)", "dark break (3.5 s)",
                     "4 x triple burst + gap (6.68 s)", "off (0.5 s)"])

        case "firmware update circular fill":
            // The palette alternates every full loop — blue fill, then amber
            // fill — for 4 cycles at 2000 ms each.
            let blueFill = step("Blue fill", length: .seconds(2)) { c in
                c.animationType = .liquidFill
                c.primaryColor = blue
            }
            let amberFill = step("Amber fill", length: .seconds(2)) { c in
                c.animationType = .liquidFill
                c.primaryColor = amber
            }
            return (RingTimeline(segments: [blueFill, amberFill], loops: true),
                    ["blue fill (2 s)", "amber fill (2 s)", "looped for 4 cycles"])

        case "firmware update comet":
            // Same alternation, as a comet at 1700 ms a lap for 6 cycles.
            let blueComet = step("Blue comet", length: .rotations(1)) { c in
                c.patternStyle = .spin
                c.speed = 1000.0 / 1700.0
                c.trailFraction = 1.0 / 16.0
                c.primaryColor = blue
            }
            let amberComet = step("Amber comet", length: .rotations(1)) { c in
                c.patternStyle = .spin
                c.speed = 1000.0 / 1700.0
                c.trailFraction = 1.0 / 16.0
                c.primaryColor = amber
            }
            return (RingTimeline(segments: [blueComet, amberComet], loops: true),
                    ["blue comet (1.7 s)", "amber comet (1.7 s)", "looped for 6 cycles"])

        default:
            return nil
        }
    }

    /// `cycles` repetitions of "N quick flashes, then a dark gap".
    ///
    /// Each burst is one step using the app's own Flash style with a
    /// matching `flashCount`, rather than N separate on/off steps — the
    /// primitive already renders exactly this, and three steps per burst
    /// would make a four-cycle alarm a twenty-step document to edit.
    private static func burstCycles(
        cycles: Int, flashes: Int,
        onMs: Double, offMs: Double, gapMs: Double,
        color: Color
    ) -> [TimelineSegment] {
        let cycleMs = onMs + offMs
        var steps: [TimelineSegment] = []
        for index in 1...cycles {
            steps.append(
                step("Burst \(index)", length: .seconds(Double(flashes) * cycleMs / 1000)) { c in
                    c.patternStyle = .flash
                    c.flashCount = flashes
                    c.blinkRate = 1000 / cycleMs
                    c.primaryColor = color
                }
            )
            steps.append(step("Gap \(index)", length: .seconds(gapMs / 1000)) { $0.patternStyle = .off })
        }
        return steps
    }

    /// The sibling module a pattern hands off to, if it does.
    ///
    /// `wifi_critical` is nothing but `return schedule_bluetooth_critical(...)`,
    /// and `wifi_failed` the same — the real pattern is in the other file.
    /// Read on its own, such a file has no behavior to find and imports off
    /// a keyword in its one-line description. The caller resolves the name
    /// against the folder it opened, since only it knows where that is.
    ///
    /// `schedule_steps` is excluded: that's the step player in
    /// `led_ring_core`, not a pattern module.
    public static func delegatedModule(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"return\s+schedule_([a-z0-9_]+)\s*\(\s*controller"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        let name = String(text[range])
        guard name != "steps" else { return nil }
        // Only a hand-off: a file that also defines its own body is doing
        // its own work and merely happens to call a sibling at the end.
        guard !text.contains("add_event_at_time_ms") else { return nil }
        return name
    }

    /// One timeline step, built on a config that starts at defaults and
    /// carries the ring's own physical facts.
    ///
    /// Every step gets Diode Mode and the 16-LED count because those
    /// describe the hardware, not the phase — a step that forgot them
    /// would render as a smooth arc mid-sequence and read as a glitch.
    private static func step(
        _ name: String,
        length: SegmentLength,
        fadeIn: Double = 0,
        fadeOut: Double = 0,
        configure: (RingConfig) -> Void
    ) -> TimelineSegment {
        let config = RingConfig()
        config.diodeModeEnabled = true
        config.diodeCount = ringLEDCount
        configure(config)
        return TimelineSegment(
            name: name,
            snapshot: RingPreset(name: name, config: config),
            length: length,
            fadeIn: fadeIn,
            fadeOut: fadeOut
        )
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

    /// Location of `name` as a whole word, or nil.
    ///
    /// Underscores count as word characters, which is exactly what's needed
    /// here: `\bCOLOR_GREEN\b` does not match inside `COLOR_GREEN_WHITE`,
    /// and `\bCOLOR_RED\b` does not match inside `COLOR_ALARM_RED`. A plain
    /// `contains` picked up both and imported the wrong color.
    private static func wordOccurrence(_ name: String, in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: "\\b\(name)\\b") else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return match.range.location
    }

    /// `name=<number>` keyword arguments from the scheduler call.
    private static func callKeywords(in text: String) -> [String: Double] {
        var result: [String: Double] = [:]
        guard let regex = try? NSRegularExpression(pattern: #"([a-z_]+)\s*=\s*(-?\d+(?:\.\d+)?)"#) else {
            return result
        }
        for line in text.split(separator: "\n") where line.contains("_schedule_") || line.contains("_ms=") {
            let string = String(line)
            let range = NSRange(string.startIndex..., in: string)
            regex.enumerateMatches(in: string, range: range) { match, _, _ in
                guard let match,
                      let nameRange = Range(match.range(at: 1), in: string),
                      let valueRange = Range(match.range(at: 2), in: string),
                      let value = Double(string[valueRange]) else { return }
                let name = String(string[nameRange])
                if result[name] == nil { result[name] = value }
            }
        }
        return result
    }

    /// The first bare number passed to a scheduler call — the cascade's
    /// lit-LED count.
    private static func firstPositionalNumber(in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"_schedule_battery_cascade\(controller,\s*system,\s*(\d+)"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[range])
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
