import Foundation

// The two dispatch chains the Blender exports are built from.
//
// Kept apart from `BlenderCodeGenerator.swift` because that file is mostly
// one very long Python heredoc, and burying twenty-eight Swift string
// literals in the middle of it would make both harder to read than either
// is alone. `BlenderCheck` covers the result either way.

extension CodeGenerators {

    /// The Blender build for one animation type.
    ///
    /// Exhaustive, with no `default`, and that is the entire point. These
    /// branches used to be string literals inside the Python heredoc,
    /// hand-mirrored from this enum — so adding a case compiled fine and
    /// then fell through to the generic stand-in, announcing itself only on
    /// Blender's console. Now a new case stops the build here until someone
    /// writes its body.
    ///
    /// Bodies are plain Python, dedented; `blenderAnimationChain` re-indents
    /// them into the emitted script.
    static func blenderAnimationBody(_ type: RingAnimationType) -> String {
        switch type {
        case .wave:
            return """
            # A conic gradient doesn't exist natively on a Blender curve,
            # so the sweep is approximated as two colored half-arcs
            # rotating together — the color boundary sweeping around
            # reads as the same continuous motion.
            a = _ring_curve("Nexus_WaveA", RADIUS, TUBE, PRIMARY, glow_strength, bevel_start=0.0, bevel_end=0.5)
            b = _ring_curve("Nexus_WaveB", RADIUS, TUBE, SECONDARY, glow_strength, bevel_start=0.5, bevel_end=1.0)
            for obj in (a, b):
                _driver(obj, "rotation_euler", "ringpod_phase(frame)", index=2)
            """

        case .chasing:
            return """
            trail = p["trail_fraction"]
            _ring_curve("Nexus_Track", RADIUS, TUBE * 0.6, PRIMARY, 0.3)
            if p["chasing_draw_undraw"]:
                ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength, bevel_end=0.0001)
                _driver(ring.data, "bevel_factor_end", f"max(math.sin(ringpod_fraction(frame) * math.pi) * {trail}, 0.0001)")
            else:
                ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength, bevel_end=trail)
            _driver(ring, "rotation_euler", "ringpod_phase(frame)", index=2)
            """

        case .dualChase:
            return """
            trail = p["trail_fraction"]
            _ring_curve("Nexus_Track", RADIUS, TUBE * 0.6, PRIMARY, 0.3)
            a = _ring_curve("Nexus_ArcA", RADIUS, TUBE, PRIMARY, glow_strength, bevel_end=trail)
            _driver(a, "rotation_euler", "ringpod_phase(frame)", index=2)
            b = _ring_curve("Nexus_ArcB", RADIUS, TUBE, SECONDARY, glow_strength, bevel_end=trail)
            _driver(b, "rotation_euler", "-ringpod_phase(frame)", index=2)
            """

        case .pulse:
            return """
            ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength)
            _driver(ring.data, "bevel_depth", f"{TUBE} * (0.7 + 0.6 * ringpod_pulse(frame))")
            """

        case .liquidFill:
            return """
            _ring_curve("Nexus_Track", RADIUS, TUBE * 0.6, PRIMARY, 0.3)
            fill = _ring_curve("Nexus_Fill", RADIUS, TUBE, PRIMARY, glow_strength, bevel_end=0.5)
            fill.rotation_euler.z = math.pi / 2  # fill originates at the bottom, like the app
            _driver(
                fill.data, "bevel_factor_end",
                "min(max((math.sin(ringpod_phase(frame) * 0.35) + 1) / 2 + "
                "math.sin(ringpod_phase(frame) * 1.8) * 0.04, 0.02), 0.98)"
            )
            """

        case .ripple:
            return """
            _ring_curve("Nexus_Track", RADIUS, TUBE, PRIMARY, 0.5)
            for i in range(3):
                color = PRIMARY if i % 2 == 0 else SECONDARY
                band = _ring_curve(f"Nexus_Wave{i}", RADIUS, TUBE, color, glow_strength)
                local_t = f"((ringpod_fraction(frame) + {i} / 3) % 1)"
                _driver(band, "scale", f"1 + {local_t} * 0.6", index=0)
                _driver(band, "scale", f"1 + {local_t} * 0.6", index=1)
                _drive_emission(band, f"(1 - {local_t}) * {glow_strength}")
            """

        case .aurora:
            return """
            _ring_curve("Nexus_Track", RADIUS, TUBE * 0.4, PRIMARY, 0.2)
            for i in range(3):
                seed = (math.sin(i * 12.9898) * 43758.5453) % 1
                color = PRIMARY if i % 2 == 0 else SECONDARY
                band = _ring_curve(
                    f"Nexus_Band{i}", RADIUS, TUBE * 1.5, color, glow_strength,
                    bevel_end=0.22 + seed * 0.16
                )
                _driver(band, "rotation_euler", f"ringpod_phase(frame) * (0.12 + {seed} * 0.22) + {seed} * 2 * math.pi", index=2)
            """

        case .alternating:
            return """
            count = max(int(p["diode_count"]), 1)
            for i in range(count):
                angle = (i / count) * 2 * math.pi - math.pi / 2
                pos = (math.cos(angle) * RADIUS, math.sin(angle) * RADIUS, 0)
                color = PRIMARY if i % 2 == 0 else SECONDARY
                dot = _dot(f"Nexus_Dot{i}", pos, TUBE / 2, color, glow_strength)
                blink = "((math.sin(ringpod_phase(frame)) + 1) / 2)"
                expr = f"{blink} * {glow_strength}" if i % 2 == 0 else f"(1 - {blink}) * {glow_strength}"
                _drive_emission(dot, expr)
            """

        case .sparkle:
            return """
            count = max(int(p["diode_count"]), 1)
            for i in range(count):
                angle = (i / count) * 2 * math.pi - math.pi / 2
                pos = (math.cos(angle) * RADIUS, math.sin(angle) * RADIUS, 0)
                color = PRIMARY if i % 2 == 0 else SECONDARY
                seed = (math.sin(i * 12.9898) * 43758.5453) % 1
                dot = _dot(f"Nexus_Dot{i}", pos, TUBE / 2, color, glow_strength)
                expr = (
                    f"max(0, 1 - (((frame / (bpy.context.scene.render.fps or 24)) * {p['speed']} "
                    f"* (0.5 + {seed}) + {seed} * 4) % 1) * 4) * {glow_strength}"
                )
                _drive_emission(dot, expr)
            """

        case .equalizer:
            return """
            count = max(int(p["diode_count"]), 4)
            seg = (1 / count) * 0.7
            _ring_curve("Nexus_Track", RADIUS, TUBE * 0.4, PRIMARY, 0.2)
            for i in range(count):
                start = i / count
                color = PRIMARY if i % 2 == 0 else SECONDARY
                seed = (math.sin(i * 12.9898) * 43758.5453) % 1
                bar = _ring_curve(f"Nexus_Bar{i}", RADIUS, TUBE, color, glow_strength, bevel_start=start, bevel_end=start + seg)
                value = f"min((math.sin(ringpod_phase(frame) * (0.6 + {seed} * 0.8) + {seed} * 2 * math.pi) + 1) / 2, 1)"
                _driver(bar.data, "bevel_depth", f"{TUBE} * (0.3 + {value} * 0.7)")
            """

        case .multiChase:
            return """
            trail = p["trail_fraction"]
            # One comet per color, evenly spaced and travelling
            # together. Approximated with two rotating arc segments
            # (the two colors this script carries) rather than
            # `diode_count` individually-driven objects, which would
            # mean dozens of curves and drivers per scene for a look
            # that reads much the same in 3D.
            for k, color in enumerate((PRIMARY, SECONDARY)):
                start = k / 2
                seg = _ring_curve(f"Nexus_Chase{k}", RADIUS, TUBE, color, glow_strength,
                                  bevel_start=start, bevel_end=start + max(trail, 0.02))
                _driver(seg, "rotation_euler", "ringpod_phase(frame)", index=2)
            """

        case .bloom:
            return """
            # An approximation, and the furthest from the app of
            # any branch here. In the app each patch surfaces
            # somewhere new every cycle, growing from and shrinking
            # back to nothing; reproducing that needs drivers on each
            # curve's bevel_factor_start/end, not just emission. What
            # this builds is six fixed patches whose brightness swells
            # on their own rates — right palette and rhythm, static
            # positions. Blur and additive overlap are dropped too,
            # both needing a compositor pass.
            trail = p["trail_fraction"]
            for i in range(6):
                width_seed = (math.sin(i * 12.9898) * 43758.5453) % 1
                place_seed = (math.sin((i + 97) * 12.9898) * 43758.5453) % 1
                rate_seed = (math.sin((i + 211) * 12.9898) * 43758.5453) % 1
                length = max(trail, 0.02) * (0.35 + width_seed * 1.65)
                center = i / 6 + (place_seed - 0.5) / 6
                color = PRIMARY if i % 2 == 0 else SECONDARY
                patch_obj = _ring_curve(f"Nexus_Bloom{i}", RADIUS, TUBE, color, glow_strength,
                                        bevel_start=max(center - length / 2, 0.0),
                                        bevel_end=min(center + length / 2, 1.0))
                rate = f"{speed} * 0.18 * (0.5 + {rate_seed} * 1.2)"
                swell = (f"((math.sin(frame / (bpy.context.scene.render.fps or 24) "
                         f"* {rate} * 2 * math.pi + {rate_seed} * 2 * math.pi) + 1) / 2)")
                _drive_emission(patch_obj, f"pow({swell}, 1.8) * {glow_strength}")
            """

        case .wobble:
            return """
            # Wobble — approximated as a breathing tube thickness rather
            # than true per-vertex radial noise, which would need a
            # Geometry Nodes driver setup beyond the scope of this script.
            ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength)
            _driver(ring.data, "bevel_depth", f"{TUBE} * (0.85 + 0.3 * ringpod_pulse(frame, period_cycles=0.3))")
            """
        }
    }

    /// The Blender build for one cue style. Exhaustive for the same reason
    /// as `blenderAnimationBody` — see its comment.
    ///
    /// Cases that share a body share a `case` list here, which is how the
    /// old `style in ("off", "notApplicable")` branch survives the move
    /// intact rather than becoming two identical branches.
    static func blenderCueStyleBody(_ style: LEDPatternStyle) -> String {
        switch style {
        case .continuousAnimation:
            return """
            _build_continuous_animation()
            """

        case .solid:
            return """
            _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength)
            """

        case .off, .notApplicable:
            return """
            _ring_curve("Nexus_Ring", RADIUS, TUBE, (1, 1, 1), 0.3)
            """

        case .earConOnly:
            return """
            # Audio-only cue — no LED motion in the app either, so this is
            # just a faint static ring for context, not an attempt at a
            # speaker icon.
            _ring_curve("Nexus_Ring", RADIUS, TUBE * 0.6, (1, 1, 1), 0.15)
            """

        case .custom:
            return """
            _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength * 0.5)
            """

        case .flash:
            return """
            ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength)
            _drive_emission(ring, f"ringpod_flash(frame, {speed}) * {glow_strength}")
            """

        case .quickFlash:
            return """
            ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength)
            _drive_emission(ring, f"ringpod_quick_flash(frame, {flash_count}) * {glow_strength}")
            """

        case .ripple:
            return """
            _ring_curve("Nexus_Track", RADIUS, TUBE * 0.4, PRIMARY, 0.2)
            for i in range(2):
                color = PRIMARY if i % 2 == 0 else SECONDARY
                band = _ring_curve(f"Nexus_Ripple{i}", RADIUS, TUBE * 0.6, color, glow_strength)
                eased = f"ringpod_ripple_progress(frame, {speed}, {i})"
                _driver(band, "scale", f"0.55 + 0.55 * {eased}", index=0)
                _driver(band, "scale", f"0.55 + 0.55 * {eased}", index=1)
                _drive_emission(band, f"(1 - {eased}) * {glow_strength}")
            """

        case .transitionToSolid:
            return """
            ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength)
            _drive_emission(ring, f"ringpod_envelope(frame, 0.5, {hold}, {fade}) * {glow_strength}")
            """

        case .spinThenSolidFade:
            return """
            # Approximated as a continuously-rotating full ring that
            # brightens, holds, then fades on the app's own timing — the
            # "grows from a small arc" detail is dropped rather than
            # animating bevel_factor and emission from two envelopes at
            # once (the same kind of simplification Wobble uses above for
            # its radial noise).
            ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength)
            _driver(ring, "rotation_euler", "ringpod_phase(frame)", index=2)
            _drive_emission(ring, f"ringpod_envelope(frame, 1.1 / max({speed}, 0.05), {hold}, {fade}) * {glow_strength}")
            """

        case .pulseAccelerateThenSolidFade:
            return """
            ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength)
            t_expr = f"ringpod_envelope_t(frame, 2.2, {hold}, {fade})"
            _drive_emission(
                ring,
                f"ringpod_envelope(frame, 2.2, {hold}, {fade}) * "
                f"(0.85 + 0.15 * math.sin({t_expr} * (1.5 + {t_expr} * 4) * 2 * math.pi)) * {glow_strength}"
            )
            """

        case .rainbowThenWhiteFade:
            return """
            # True continuous hue-cycling needs a per-frame driver on the
            # material's individual R/G/B Emission Color channels, which
            # this script skips for simplicity — timing (spin, hold, fade)
            # is exact; the color itself stays this cue's primary color
            # rather than sweeping the full rainbow.
            ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength)
            _driver(ring, "rotation_euler", "ringpod_phase(frame)", index=2)
            _drive_emission(ring, f"ringpod_envelope(frame, 1.5 / max({speed}, 0.05), {hold}, {fade}) * {glow_strength}")
            """

        case .spin:
            return """
            # Primitive: turns continuously at `speed` revolutions per
            # second with steady emission. No envelope — a timeline step
            # decides how long it runs and whether it fades, rather than
            # the style baking in a hold and fade of its own.
            ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength,
                               bevel_start=0.0, bevel_end=0.28)
            _driver(ring, "rotation_euler", "ringpod_phase(frame)", index=2)
            _drive_emission(ring, f"{glow_strength}")
            """

        case .pulseAccelerate:
            return """
            # Primitive: the accelerating breath on its own, restarting its
            # 2.2s rate ramp instead of settling into a hold.
            ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength)
            t_expr = "((frame / (bpy.context.scene.render.fps or 24)) % 2.2)"
            _drive_emission(
                ring,
                f"(0.4 + 0.6 * (math.sin({t_expr} * (1.5 + ({t_expr} / 2.2) * 8) "
                f"* 2 * math.pi) + 1) / 2) * {glow_strength}"
            )
            """

        case .rainbow:
            return """
            # Same caveat as rainbowThenWhiteFade below: sweeping hue needs
            # per-frame drivers on the material's individual R/G/B emission
            # channels, which this script deliberately skips. The rotation
            # and timing are exact; the color stays the primary.
            ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength)
            _driver(ring, "rotation_euler", "ringpod_phase(frame)", index=2)
            _drive_emission(ring, f"{glow_strength}")
            """

        case .voiceAssistantColor:
            return """
            a = _ring_curve("Nexus_VoiceA", RADIUS, TUBE, PRIMARY, glow_strength, bevel_start=0.0, bevel_end=0.5)
            b = _ring_curve("Nexus_VoiceB", RADIUS, TUBE, SECONDARY, glow_strength, bevel_start=0.5, bevel_end=1.0)
            for obj in (a, b):
                _driver(obj, "rotation_euler", "ringpod_phase(frame)", index=2)
            """
        }
    }

    /// The `if`/`elif` chain, built from `allCases` so a case cannot be
    /// left out of the emitted script even if it has a body above.
    ///
    /// Order comes from the enum's own declaration order rather than the
    /// chain's previous hand-written order. Safe because every condition is
    /// an equality on a distinct value, so no branch can shadow another.
    static var blenderAnimationChain: String {
        chain(RingAnimationType.allCases.map { ($0.rawValue, blenderAnimationBody($0)) },
              variable: "anim", headerIndent: 4)
    }

    /// See `blenderAnimationChain`.
    static var blenderCueStyleChain: String {
        chain(LEDPatternStyle.allCases.map { ($0.rawValue, blenderCueStyleBody($0)) },
              variable: "style", headerIndent: 0)
    }

    /// Assembles one chain. Bodies are indented four past their header, and
    /// consecutive cases with identical bodies share a branch — which is
    /// what keeps `off` and `notApplicable` emitting as one `style in (...)`
    /// test rather than two copies of the same three lines.
    private static func chain(
        _ branches: [(value: String, body: String)],
        variable: String,
        headerIndent: Int
    ) -> String {
        var grouped: [(values: [String], body: String)] = []
        for branch in branches {
            if var last = grouped.last, last.body == branch.body {
                last.values.append(branch.value)
                grouped[grouped.count - 1] = last
            } else {
                grouped.append(([branch.value], branch.body))
            }
        }

        let header = String(repeating: " ", count: headerIndent)
        let bodyPad = String(repeating: " ", count: headerIndent + 4)
        let rendered = grouped.enumerated().map { index, group -> String in
            let keyword = index == 0 ? "if" : "elif"
            let test: String
            if group.values.count == 1 {
                test = "\(variable) == \"\(group.values[0])\""
            } else {
                test = "\(variable) in (" + group.values.map { "\"\($0)\"" }.joined(separator: ", ") + ")"
            }
            let body = group.body
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.isEmpty ? "" : bodyPad + $0 }
                .joined(separator: "\n")
            return "\(header)\(keyword) \(test):\n\(body)"
        }
        return rendered.joined(separator: "\n\n") + "\n"
    }
}
