import Foundation
import SwiftUI

/// Blender-side counterpart to `CodeGenerators`' SwiftUI/Compose/Web
/// exporters — self-contained Python scripts (`bpy`) a 3D-side designer
/// can paste into Blender's Scripting tab to see a ring reproduced as a
/// real, driver-animated scene object, plus the inverse: reading that same
/// script back to update a live `RingConfig`/`LEDCueParameters`. Covers
/// both Nexus's own current ring (`blenderCode`) and a single
/// Cue Library entry (`blenderCueCode`) — the same split `CodeGenerators`'
/// other three exporters already have between `swiftUICode`/`swiftUICueCode`
/// etc.
///
/// Neither is a big per-case switch on the Swift side — each fixed Python
/// body branches on its own params dict at Blender-run-time instead
/// (`NEXUS_PARAMS["animation_type"]` / `["style"]`). That means a
/// designer can flip that one string in Blender and re-run to explore a
/// different animation entirely, without re-exporting from the app —
/// closer to what "translate the ring animations for Blender" actually
/// implies than a static one-shot dump would be. The cue script's
/// `continuousAnimation` style literally calls the same
/// `_build_continuous_animation()` Python function Nexus
/// script does, defined once in the shared helpers below, so the two
/// never drift apart.
///
/// Only the parameters a 3D designer would plausibly want to hand-tune are
/// round-tripped (style/type, easing, speed, geometry, colors, glow,
/// timing) — the same "curated subset" reasoning `RingPreset` already uses
/// for its own exclusions (voice/API-key fields, background image data,
/// etc. never belonged in a shareable export either).
public extension CodeGenerators {
    static func blenderCode(config: RingConfig) -> String {
        if let placeholder = patternStyleExportPlaceholder(config: config) { return placeholder }

        let primaryHex = config.primaryColor.hexString
        let secondaryHex = config.secondaryColor.hexString
        let drawUndraw = config.chasingFillStyle == .drawUndraw

        let header = """
        # ============================================================
        # Nexus -> Blender import (current ring)
        # Animation: \(config.animationType.rawValue) - Easing: \(config.easingStyle.rawValue)
        #
        # Paste into Blender's Scripting tab and hit Run (or run headless
        # via `blender --python this_file.py`). Safe to re-run — it deletes
        # and rebuilds its own "Nexus_*" objects each time rather than
        # duplicating them. Built for Blender 4.0+; on older versions the
        # material falls back to a flat Base Color (no glow), but the
        # geometry and motion still work.
        #
        # NEXUS_PARAMS below is the only part "Import Blender Python…"
        # in Nexus reads back — change these values (including
        # animation_type, to preview a different one), re-run in Blender,
        # then use Import in the app to carry your edits back into the
        # live ring. Everything after the params block is generated scene
        # setup and doesn't need to be hand-edited.
        # ============================================================

        import bpy
        import bmesh
        import math

        NEXUS_PARAMS = {
            "animation_type": "\(config.animationType.rawValue)",
            "easing": "\(config.easingStyle.rawValue)",
            "speed": \(config.speed),
            "diameter": \(config.previewDiameter),
            "line_width": \(config.lineWidth),
            "trail_fraction": \(config.trailFraction),
            "diode_count": \(Int(config.diodeCount.rounded())),
            "chasing_draw_undraw": \(drawUndraw ? "True" : "False"),
            "primary_color": "\(primaryHex)",
            "secondary_color": "\(secondaryHex)",
            "glow_enabled": \(config.glowEnabled ? "True" : "False"),
            "glow_radius": \(config.glowRadius),
        }
        """

        let tail = """

        _build_continuous_animation()

        if p["glow_enabled"]:
            try:
                bpy.context.scene.eevee.use_bloom = True
            except AttributeError:
                pass  # Renamed/moved in some Blender versions — enable
                      # Bloom manually under Render Properties if needed.

        print(f"Nexus: built '{p['animation_type']}' in Blender.")
        """

        return header + "\n\n" + blenderHelpers + tail
    }

    /// The Cue Library's counterpart — bakes in whichever `LEDPatternStyle`
    /// (plus colors/speed/timing) the given cue currently has, exactly
    /// like `swiftUICueCode`/`composeCueCode`/`webCueCode` bake in this
    /// cue's current look rather than exporting a runtime switch over all
    /// 14 styles.
    static func blenderCueCode(cue: LEDCue, parameters: LEDCueParameters) -> String {
        let primaryHex = Color(hex: parameters.primaryColorHex).hexString
        let secondaryHex = Color(hex: parameters.secondaryColorHex).hexString
        let clampedSpeed = max(parameters.speed, 0.05)
        let drawUndraw = parameters.chasingFillStyle == .drawUndraw

        let header = """
        # ============================================================
        # Nexus -> Blender import (Cue Library)
        # Cue: \(cue.name) (\([cue.category, cue.subcategory].compactMap { $0 }.joined(separator: " · ")))
        # Style: \(parameters.style.displayName)
        #
        # Spec sheet reference: \(cue.specText)
        #
        # Paste into Blender's Scripting tab and hit Run (or run headless
        # via `blender --python this_file.py`). Safe to re-run — it deletes
        # and rebuilds its own "Nexus_*" objects each time rather than
        # duplicating them. Built for Blender 4.0+; on older versions the
        # material falls back to a flat Base Color (no glow), but the
        # geometry and motion still work.
        #
        # NEXUS_PARAMS below is the only part "Import Blender Python…"
        # in Nexus reads back — change these values (including style,
        # to preview a different cue behavior), re-run in Blender, then use
        # Import in the app to carry your edits back into this cue.
        # Everything after the params block is generated scene setup and
        # doesn't need to be hand-edited.
        # ============================================================

        import bpy
        import bmesh
        import math

        NEXUS_PARAMS = {
            "style": "\(parameters.style.rawValue)",
            "animation_type": "\(parameters.animationType.rawValue)",
            "easing": "\(parameters.easingStyle.rawValue)",
            "speed": \(clampedSpeed),
            "diameter": 160,
            "line_width": \(parameters.lineWidth),
            "trail_fraction": \(parameters.trailFraction),
            "diode_count": \(Int(parameters.diodeCount.rounded())),
            "chasing_draw_undraw": \(drawUndraw ? "True" : "False"),
            "flash_count": \(parameters.flashCount),
            "hold_seconds": \(parameters.holdSeconds),
            "fade_out_seconds": \(parameters.fadeOutSeconds),
            "primary_color": "\(primaryHex)",
            "secondary_color": "\(secondaryHex)",
            "glow_enabled": \(parameters.glowEnabled ? "True" : "False"),
            "glow_radius": \(parameters.glowRadius),
        }
        """

        return header + "\n\n" + blenderHelpers + "\n\n" + blenderCueDispatch
    }

    // MARK: - Shared preamble (helpers + Nexus's 11-animation-
    // type dispatch, as a callable function so the Cue script's own
    // `continuousAnimation` style can reuse it verbatim instead of
    // duplicating it).

    private static var blenderHelpers: String {
        """
        p = NEXUS_PARAMS


        def _hex_to_rgb(hex_str):
            s = hex_str.lstrip('#')
            return tuple(int(s[i:i + 2], 16) / 255 for i in (0, 2, 4))


        PRIMARY = _hex_to_rgb(p["primary_color"])
        SECONDARY = _hex_to_rgb(p["secondary_color"])
        SCALE = 0.01  # Nexus px -> Blender meters, purely a display convenience
        RADIUS = (p["diameter"] / 2) * SCALE
        TUBE = max(p["line_width"] * SCALE, 0.001)
        GLOW_STRENGTH = 3.0 if p["glow_enabled"] else 1.4


        def _ease(t, style):
            if style == "Ease In":
                return t * t
            if style == "Ease Out":
                return 1 - (1 - t) * (1 - t)
            if style == "Ease In Out":
                return 2 * t * t if t < 0.5 else 1 - pow(-2 * t + 2, 2) / 2
            if style == "Spring":
                decay = math.exp(-6 * t)
                return t + 0.3 * decay * math.sin(t * math.pi * 6)
            return t  # Linear


        def _cycle(frame):
            fps = bpy.context.scene.render.fps or 24
            cycles = (frame / fps) * p["speed"]
            n = math.floor(cycles)
            return n, cycles - n


        def ringpod_phase(frame):
            n, f = _cycle(frame)
            return (n + _ease(f, p["easing"])) * 2 * math.pi


        def ringpod_fraction(frame):
            return _cycle(frame)[1]


        def ringpod_pulse(frame, period_cycles=1.0, offset=0.0):
            # Generic 0..1 breathing value, one full sine per `period_cycles`
            # cycles of the ring's own speed — reused for Pulse/Wobble.
            fps = bpy.context.scene.render.fps or 24
            t = (frame / fps) * p["speed"] / max(period_cycles, 0.001) + offset
            return (math.sin(t * 2 * math.pi) + 1) / 2


        def ringpod_flash(frame, speed):
            fps = bpy.context.scene.render.fps or 24
            period = 1 / max(speed, 0.05)
            t = (frame / fps) % period
            return 1 if t < period / 2 else 0


        def ringpod_quick_flash(frame, flash_count):
            fps = bpy.context.scene.render.fps or 24
            single = 0.14
            flash_window = max(flash_count, 1) * single * 2
            cycle = flash_window + 0.8
            t = (frame / fps) % cycle
            if t < flash_window:
                return 1 if (t % (single * 2)) < single else 0
            return 0


        def ringpod_ripple_progress(frame, speed, index):
            fps = bpy.context.scene.render.fps or 24
            cycle = max(1.1 / max(speed, 0.05) + 0.2, 0.2)
            t = (frame / fps) % cycle
            raw = (t / cycle + index * 0.5) % 1.0
            return _ease(raw, p["easing"])


        def ringpod_envelope(frame, ramp, hold, fade):
            # 0..1 brightness envelope: ramps up over `ramp` seconds, holds
            # at 1 for `hold` seconds, fades over `fade` seconds, then rests
            # briefly before looping — matches the app's own
            # transitionToSolid/spinThenSolidFade/pulseAccelerateThenSolidFade/
            # rainbowThenWhiteFade cue timing.
            fps = bpy.context.scene.render.fps or 24
            cycle = max(ramp + hold + fade + 0.6, 0.2)
            t = (frame / fps) % cycle
            if t < ramp:
                return max(t / max(ramp, 0.001), 0.05)
            if t < ramp + hold:
                return 1.0
            if t < ramp + hold + fade:
                return max(1 - (t - ramp - hold) / max(fade, 0.001), 0.05)
            return 0.05


        def ringpod_envelope_t(frame, ramp, hold, fade):
            # Raw elapsed seconds within `ringpod_envelope`'s own cycle —
            # used alongside it to drive pre-hold motion (e.g. an
            # accelerating pulse rate).
            fps = bpy.context.scene.render.fps or 24
            cycle = max(ramp + hold + fade + 0.6, 0.2)
            return (frame / fps) % cycle


        bpy.app.driver_namespace["ringpod_phase"] = ringpod_phase
        bpy.app.driver_namespace["ringpod_fraction"] = ringpod_fraction
        bpy.app.driver_namespace["ringpod_pulse"] = ringpod_pulse
        bpy.app.driver_namespace["ringpod_flash"] = ringpod_flash
        bpy.app.driver_namespace["ringpod_quick_flash"] = ringpod_quick_flash
        bpy.app.driver_namespace["ringpod_ripple_progress"] = ringpod_ripple_progress
        bpy.app.driver_namespace["ringpod_envelope"] = ringpod_envelope
        bpy.app.driver_namespace["ringpod_envelope_t"] = ringpod_envelope_t

        # ---- cleanup from any previous run ----
        for name in list(bpy.data.objects.keys()):
            if name.startswith("Nexus_"):
                bpy.data.objects.remove(bpy.data.objects[name], do_unlink=True)
        for name in list(bpy.data.materials.keys()):
            if name.startswith("Nexus_"):
                bpy.data.materials.remove(bpy.data.materials[name])


        def _material(name, color, strength=2.0):
            mat = bpy.data.materials.new(name)
            mat.use_nodes = True
            bsdf = mat.node_tree.nodes.get("Principled BSDF")
            if bsdf is not None:
                if "Emission Color" in bsdf.inputs:
                    bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
                    bsdf.inputs["Emission Strength"].default_value = strength
                else:
                    # Pre-4.0 Blender: no built-in emission input on
                    # Principled BSDF — fall back to a flat Base Color.
                    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
            return mat


        def _driver(target, data_path, expression, index=None):
            result = target.driver_add(data_path) if index is None else target.driver_add(data_path, index)
            for fc in (result if isinstance(result, list) else [result]):
                fc.driver.type = 'SCRIPTED'
                fc.driver.expression = expression


        def _emission_input(obj):
            bsdf = obj.data.materials[0].node_tree.nodes.get("Principled BSDF")
            if bsdf is not None and "Emission Strength" in bsdf.inputs:
                return bsdf.inputs["Emission Strength"]
            return None


        def _drive_emission(obj, expression):
            inp = _emission_input(obj)
            if inp is not None:
                _driver(inp, "default_value", expression)


        def _ring_curve(name, radius, bevel_depth, color, strength=2.0, bevel_start=0.0, bevel_end=1.0):
            curve = bpy.data.curves.new(name, type='CURVE')
            curve.dimensions = '3D'
            curve.bevel_depth = bevel_depth
            curve.bevel_resolution = 4
            curve.resolution_u = 24
            curve.use_fill_caps = True
            spline = curve.splines.new('BEZIER')
            spline.bezier_points.add(3)
            k = 0.5522847498  # Bezier circle magic number
            pts = [
                ((radius, 0, 0), (radius, -k * radius, 0), (radius, k * radius, 0)),
                ((0, radius, 0), (-k * radius, radius, 0), (k * radius, radius, 0)),
                ((-radius, 0, 0), (-radius, k * radius, 0), (-radius, -k * radius, 0)),
                ((0, -radius, 0), (k * radius, -radius, 0), (-k * radius, -radius, 0)),
            ]
            for i, (co, left, right) in enumerate(pts):
                bp = spline.bezier_points[i]
                bp.co, bp.handle_left, bp.handle_right = co, left, right
                bp.handle_left_type = bp.handle_right_type = 'FREE'
            spline.use_cyclic_u = True
            curve.bevel_factor_start = bevel_start
            curve.bevel_factor_end = bevel_end
            obj = bpy.data.objects.new(name, curve)
            bpy.context.collection.objects.link(obj)
            obj.data.materials.append(_material(name + "_Mat", color, strength))
            return obj


        def _dot(name, position, radius, color, strength=2.0):
            mesh = bpy.data.meshes.new(name)
            obj = bpy.data.objects.new(name, mesh)
            bpy.context.collection.objects.link(obj)
            bm = bmesh.new()
            bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=radius)
            bm.to_mesh(mesh)
            bm.free()
            obj.location = position
            obj.data.materials.append(_material(name + "_Mat", color, strength))
            return obj


        def _build_continuous_animation():
            # Nexus's 11 continuous "AI thinking" animation
            # types, translated to native Blender techniques — curve bevel
            # trims stand in for SwiftUI's `.trim(from:to:)`, drivers stand
            # in for `TimelineView`. Shared verbatim between Nexus's own
            # export and a Cue Library cue whose style is
            # "continuousAnimation", so the two never drift apart.
            anim = p["animation_type"]
            glow_strength = GLOW_STRENGTH

            if anim == "Wave":
                # A conic gradient doesn't exist natively on a Blender curve,
                # so the sweep is approximated as two colored half-arcs
                # rotating together — the color boundary sweeping around
                # reads as the same continuous motion.
                a = _ring_curve("Nexus_WaveA", RADIUS, TUBE, PRIMARY, glow_strength, bevel_start=0.0, bevel_end=0.5)
                b = _ring_curve("Nexus_WaveB", RADIUS, TUBE, SECONDARY, glow_strength, bevel_start=0.5, bevel_end=1.0)
                for obj in (a, b):
                    _driver(obj, "rotation_euler", "ringpod_phase(frame)", index=2)

            elif anim == "Chasing":
                trail = p["trail_fraction"]
                _ring_curve("Nexus_Track", RADIUS, TUBE * 0.6, PRIMARY, 0.3)
                if p["chasing_draw_undraw"]:
                    ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength, bevel_end=0.0001)
                    _driver(ring.data, "bevel_factor_end", f"max(math.sin(ringpod_fraction(frame) * math.pi) * {trail}, 0.0001)")
                else:
                    ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength, bevel_end=trail)
                _driver(ring, "rotation_euler", "ringpod_phase(frame)", index=2)

            elif anim == "Dual Chase":
                trail = p["trail_fraction"]
                _ring_curve("Nexus_Track", RADIUS, TUBE * 0.6, PRIMARY, 0.3)
                a = _ring_curve("Nexus_ArcA", RADIUS, TUBE, PRIMARY, glow_strength, bevel_end=trail)
                _driver(a, "rotation_euler", "ringpod_phase(frame)", index=2)
                b = _ring_curve("Nexus_ArcB", RADIUS, TUBE, SECONDARY, glow_strength, bevel_end=trail)
                _driver(b, "rotation_euler", "-ringpod_phase(frame)", index=2)

            elif anim == "Pulse":
                ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength)
                _driver(ring.data, "bevel_depth", f"{TUBE} * (0.7 + 0.6 * ringpod_pulse(frame))")

            elif anim == "Liquid Fill":
                _ring_curve("Nexus_Track", RADIUS, TUBE * 0.6, PRIMARY, 0.3)
                fill = _ring_curve("Nexus_Fill", RADIUS, TUBE, PRIMARY, glow_strength, bevel_end=0.5)
                fill.rotation_euler.z = math.pi / 2  # fill originates at the bottom, like the app
                _driver(
                    fill.data, "bevel_factor_end",
                    "min(max((math.sin(ringpod_phase(frame) * 0.35) + 1) / 2 + "
                    "math.sin(ringpod_phase(frame) * 1.8) * 0.04, 0.02), 0.98)"
                )

            elif anim == "Ripple":
                _ring_curve("Nexus_Track", RADIUS, TUBE, PRIMARY, 0.5)
                for i in range(3):
                    color = PRIMARY if i % 2 == 0 else SECONDARY
                    band = _ring_curve(f"Nexus_Wave{i}", RADIUS, TUBE, color, glow_strength)
                    local_t = f"((ringpod_fraction(frame) + {i} / 3) % 1)"
                    _driver(band, "scale", f"1 + {local_t} * 0.6", index=0)
                    _driver(band, "scale", f"1 + {local_t} * 0.6", index=1)
                    _drive_emission(band, f"(1 - {local_t}) * {glow_strength}")

            elif anim == "Aurora":
                _ring_curve("Nexus_Track", RADIUS, TUBE * 0.4, PRIMARY, 0.2)
                for i in range(3):
                    seed = (math.sin(i * 12.9898) * 43758.5453) % 1
                    color = PRIMARY if i % 2 == 0 else SECONDARY
                    band = _ring_curve(
                        f"Nexus_Band{i}", RADIUS, TUBE * 1.5, color, glow_strength,
                        bevel_end=0.22 + seed * 0.16
                    )
                    _driver(band, "rotation_euler", f"ringpod_phase(frame) * (0.12 + {seed} * 0.22) + {seed} * 2 * math.pi", index=2)

            elif anim == "Alternating":
                count = max(int(p["diode_count"]), 1)
                for i in range(count):
                    angle = (i / count) * 2 * math.pi - math.pi / 2
                    pos = (math.cos(angle) * RADIUS, math.sin(angle) * RADIUS, 0)
                    color = PRIMARY if i % 2 == 0 else SECONDARY
                    dot = _dot(f"Nexus_Dot{i}", pos, TUBE / 2, color, glow_strength)
                    blink = "((math.sin(ringpod_phase(frame)) + 1) / 2)"
                    expr = f"{blink} * {glow_strength}" if i % 2 == 0 else f"(1 - {blink}) * {glow_strength}"
                    _drive_emission(dot, expr)

            elif anim == "Sparkle":
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

            elif anim == "Equalizer":
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

            elif anim == "Multi Chase":
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

            elif anim == "Bloom":
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

            elif anim == "Wobble":
                # Wobble — approximated as a breathing tube thickness rather
                # than true per-vertex radial noise, which would need a
                # Geometry Nodes driver setup beyond the scope of this script.
                ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength)
                _driver(ring.data, "bevel_depth", f"{TUBE} * (0.85 + 0.3 * ringpod_pulse(frame, period_cycles=0.3))")

            else:
                # Explicit fallback. Wobble used to be the bare `else`,
                # which meant any animation type added later silently
                # rendered as Wobble. A plain glowing ring is the honest
                # stand-in, and the print names the type so it's obvious in
                # Blender's console which one had no branch.
                ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength)
                print(f"Nexus: animation '{anim}' has no dedicated Blender build — "
                      "rendered as a static ring.")
        """
    }

    // MARK: - Cue Library dispatch (the 13 non-continuous `LEDPatternStyle`
    // cases, plus a `continuousAnimation` branch that just calls the shared
    // function above).

    private static var blenderCueDispatch: String {
        """
        style = p["style"]
        speed = p["speed"]
        hold = p["hold_seconds"]
        fade = p["fade_out_seconds"]
        flash_count = p["flash_count"]
        glow_strength = GLOW_STRENGTH

        if style == "continuousAnimation":
            _build_continuous_animation()

        elif style == "solid":
            _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength)

        elif style in ("off", "notApplicable"):
            _ring_curve("Nexus_Ring", RADIUS, TUBE, (1, 1, 1), 0.3)

        elif style == "earConOnly":
            # Audio-only cue — no LED motion in the app either, so this is
            # just a faint static ring for context, not an attempt at a
            # speaker icon.
            _ring_curve("Nexus_Ring", RADIUS, TUBE * 0.6, (1, 1, 1), 0.15)

        elif style == "custom":
            _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength * 0.5)

        elif style == "flash":
            ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength)
            _drive_emission(ring, f"ringpod_flash(frame, {speed}) * {glow_strength}")

        elif style == "quickFlash":
            ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength)
            _drive_emission(ring, f"ringpod_quick_flash(frame, {flash_count}) * {glow_strength}")

        elif style == "ripple":
            _ring_curve("Nexus_Track", RADIUS, TUBE * 0.4, PRIMARY, 0.2)
            for i in range(2):
                color = PRIMARY if i % 2 == 0 else SECONDARY
                band = _ring_curve(f"Nexus_Ripple{i}", RADIUS, TUBE * 0.6, color, glow_strength)
                eased = f"ringpod_ripple_progress(frame, {speed}, {i})"
                _driver(band, "scale", f"0.55 + 0.55 * {eased}", index=0)
                _driver(band, "scale", f"0.55 + 0.55 * {eased}", index=1)
                _drive_emission(band, f"(1 - {eased}) * {glow_strength}")

        elif style == "transitionToSolid":
            ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength)
            _drive_emission(ring, f"ringpod_envelope(frame, 0.5, {hold}, {fade}) * {glow_strength}")

        elif style == "spinThenSolidFade":
            # Approximated as a continuously-rotating full ring that
            # brightens, holds, then fades on the app's own timing — the
            # "grows from a small arc" detail is dropped rather than
            # animating bevel_factor and emission from two envelopes at
            # once (the same kind of simplification Wobble uses above for
            # its radial noise).
            ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength)
            _driver(ring, "rotation_euler", "ringpod_phase(frame)", index=2)
            _drive_emission(ring, f"ringpod_envelope(frame, 1.1 / max({speed}, 0.05), {hold}, {fade}) * {glow_strength}")

        elif style == "pulseAccelerateThenSolidFade":
            ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength)
            t_expr = f"ringpod_envelope_t(frame, 2.2, {hold}, {fade})"
            _drive_emission(
                ring,
                f"ringpod_envelope(frame, 2.2, {hold}, {fade}) * "
                f"(0.85 + 0.15 * math.sin({t_expr} * (1.5 + {t_expr} * 4) * 2 * math.pi)) * {glow_strength}"
            )

        elif style == "rainbowThenWhiteFade":
            # True continuous hue-cycling needs a per-frame driver on the
            # material's individual R/G/B Emission Color channels, which
            # this script skips for simplicity — timing (spin, hold, fade)
            # is exact; the color itself stays this cue's primary color
            # rather than sweeping the full rainbow.
            ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength)
            _driver(ring, "rotation_euler", "ringpod_phase(frame)", index=2)
            _drive_emission(ring, f"ringpod_envelope(frame, 1.5 / max({speed}, 0.05), {hold}, {fade}) * {glow_strength}")

        elif style == "spin":
            # Primitive: turns continuously at `speed` revolutions per
            # second with steady emission. No envelope — a timeline step
            # decides how long it runs and whether it fades, rather than
            # the style baking in a hold and fade of its own.
            ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength,
                               bevel_start=0.0, bevel_end=0.28)
            _driver(ring, "rotation_euler", "ringpod_phase(frame)", index=2)
            _drive_emission(ring, f"{glow_strength}")

        elif style == "pulseAccelerate":
            # Primitive: the accelerating breath on its own, restarting its
            # 2.2s rate ramp instead of settling into a hold.
            ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength)
            t_expr = "((frame / (bpy.context.scene.render.fps or 24)) % 2.2)"
            _drive_emission(
                ring,
                f"(0.4 + 0.6 * (math.sin({t_expr} * (1.5 + ({t_expr} / 2.2) * 8) "
                f"* 2 * math.pi) + 1) / 2) * {glow_strength}"
            )

        elif style == "rainbow":
            # Same caveat as rainbowThenWhiteFade below: sweeping hue needs
            # per-frame drivers on the material's individual R/G/B emission
            # channels, which this script deliberately skips. The rotation
            # and timing are exact; the color stays the primary.
            ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength)
            _driver(ring, "rotation_euler", "ringpod_phase(frame)", index=2)
            _drive_emission(ring, f"{glow_strength}")

        elif style == "voiceAssistantColor":
            a = _ring_curve("Nexus_VoiceA", RADIUS, TUBE, PRIMARY, glow_strength, bevel_start=0.0, bevel_end=0.5)
            b = _ring_curve("Nexus_VoiceB", RADIUS, TUBE, SECONDARY, glow_strength, bevel_start=0.5, bevel_end=1.0)
            for obj in (a, b):
                _driver(obj, "rotation_euler", "ringpod_phase(frame)", index=2)

        else:
            # Explicit fallback. This chain used to end at
            # `else:  # voiceAssistantColor`, which meant any style added
            # later rendered as the two-arc voice assistant without
            # anything saying so. A plain solid ring is the honest
            # stand-in, and the print below names the style so it's
            # obvious in Blender's console which one had no branch.
            ring = _ring_curve("Nexus_Ring", RADIUS, TUBE, PRIMARY, glow_strength)
            _drive_emission(ring, f"{glow_strength}")
            print(f"Nexus: style '{style}' has no dedicated Blender build — "
                  "rendered as a solid ring.")

        if p["glow_enabled"]:
            try:
                bpy.context.scene.eevee.use_bloom = True
            except AttributeError:
                pass  # Renamed/moved in some Blender versions — enable
                      # Bloom manually under Render Properties if needed.

        print(f"Nexus: built cue style '{style}' in Blender.")
        """
    }
}

// MARK: - Import (Blender Python -> RingConfig / LEDCueParameters)

public enum BlenderImportError: Error {
    case unrecognizedFormat
}

public extension CodeGenerators {
    /// Reads the `NEXUS_PARAMS = { ... }` block back out of a script —
    /// either one this app exported, or a hand-edited copy of one (same
    /// keys, tweaked values, which is exactly the "see how it translates
    /// back" round trip this is for). Applies whatever fields it finds
    /// directly onto the live `config`; anything missing (e.g. a
    /// hand-written script that only kept a few keys) is simply left
    /// alone rather than failing the whole import.
    @discardableResult
    static func applyBlenderCode(_ text: String, to config: RingConfig) -> Result<Void, BlenderImportError> {
        guard let block = blenderParamsBlock(in: text) else { return .failure(.unrecognizedFormat) }

        guard
            let animationTypeRaw = blenderStringValue(for: "animation_type", in: block),
            let animationType = RingAnimationType(rawValue: animationTypeRaw),
            let speed = blenderDoubleValue(for: "speed", in: block),
            let primaryHex = blenderStringValue(for: "primary_color", in: block),
            let secondaryHex = blenderStringValue(for: "secondary_color", in: block)
        else {
            return .failure(.unrecognizedFormat)
        }

        config.animationType = animationType
        config.speed = speed
        config.primaryColor = Color(hex: primaryHex)
        config.secondaryColor = Color(hex: secondaryHex)

        if let raw = blenderStringValue(for: "easing", in: block), let easing = EasingStyle(rawValue: raw) {
            config.easingStyle = easing
        }
        if let diameter = blenderDoubleValue(for: "diameter", in: block) { config.previewDiameter = diameter }
        if let lineWidth = blenderDoubleValue(for: "line_width", in: block) { config.lineWidth = lineWidth }
        if let trail = blenderDoubleValue(for: "trail_fraction", in: block) { config.trailFraction = trail }
        if let diodeCount = blenderDoubleValue(for: "diode_count", in: block) { config.diodeCount = diodeCount }
        if let drawUndraw = blenderBoolValue(for: "chasing_draw_undraw", in: block) {
            config.chasingFillStyle = drawUndraw ? .drawUndraw : .trailingTail
        }
        if let glowEnabled = blenderBoolValue(for: "glow_enabled", in: block) { config.glowEnabled = glowEnabled }
        if let glowRadius = blenderDoubleValue(for: "glow_radius", in: block) { config.glowRadius = glowRadius }

        return .success(())
    }

    /// Same idea as `applyBlenderCode`, but for a single Cue Library entry
    /// — returns an updated `LEDCueParameters` (starting from `parameters`)
    /// rather than mutating a live object in place, since cue parameters
    /// are a plain `Codable` value owned by `LEDCueStore`, not an
    /// `ObservableObject`. Callers hand the result to
    /// `LEDCueStore.update(_:for:)`.
    static func applyBlenderCueCode(_ text: String, to parameters: LEDCueParameters) -> Result<LEDCueParameters, BlenderImportError> {
        guard let block = blenderParamsBlock(in: text) else { return .failure(.unrecognizedFormat) }

        guard
            let styleRaw = blenderStringValue(for: "style", in: block),
            let style = LEDPatternStyle(rawValue: styleRaw),
            let speed = blenderDoubleValue(for: "speed", in: block),
            let primaryHex = blenderStringValue(for: "primary_color", in: block),
            let secondaryHex = blenderStringValue(for: "secondary_color", in: block)
        else {
            return .failure(.unrecognizedFormat)
        }

        var updated = parameters
        updated.style = style
        updated.speed = speed
        updated.primaryColorHex = Color(hex: primaryHex).hexString
        updated.secondaryColorHex = Color(hex: secondaryHex).hexString

        if let raw = blenderStringValue(for: "animation_type", in: block), let animationType = RingAnimationType(rawValue: raw) {
            updated.animationType = animationType
        }
        if let raw = blenderStringValue(for: "easing", in: block), let easing = EasingStyle(rawValue: raw) {
            updated.easingStyle = easing
        }
        if let lineWidth = blenderDoubleValue(for: "line_width", in: block) { updated.lineWidth = lineWidth }
        if let trail = blenderDoubleValue(for: "trail_fraction", in: block) { updated.trailFraction = trail }
        if let diodeCount = blenderDoubleValue(for: "diode_count", in: block) { updated.diodeCount = diodeCount }
        if let drawUndraw = blenderBoolValue(for: "chasing_draw_undraw", in: block) {
            updated.chasingFillStyle = drawUndraw ? .drawUndraw : .trailingTail
        }
        if let flashCount = blenderDoubleValue(for: "flash_count", in: block) { updated.flashCount = Int(flashCount) }
        if let hold = blenderDoubleValue(for: "hold_seconds", in: block) { updated.holdSeconds = hold }
        if let fadeOut = blenderDoubleValue(for: "fade_out_seconds", in: block) { updated.fadeOutSeconds = fadeOut }
        if let glowEnabled = blenderBoolValue(for: "glow_enabled", in: block) { updated.glowEnabled = glowEnabled }
        if let glowRadius = blenderDoubleValue(for: "glow_radius", in: block) { updated.glowRadius = glowRadius }

        return .success(updated)
    }
}

private func blenderParamsBlock(in text: String) -> String? {
    guard let startRange = text.range(of: "NEXUS_PARAMS = {") else { return nil }
    guard let closeRange = text.range(of: "\n}", range: startRange.upperBound..<text.endIndex) else { return nil }
    return String(text[startRange.upperBound..<closeRange.lowerBound])
}

private func blenderStringValue(for key: String, in block: String) -> String? {
    blenderFirstMatch("\"\(key)\"\\s*:\\s*\"([^\"]*)\"", in: block)
}

private func blenderDoubleValue(for key: String, in block: String) -> Double? {
    blenderFirstMatch("\"\(key)\"\\s*:\\s*(-?[0-9.]+)", in: block).flatMap(Double.init)
}

private func blenderBoolValue(for key: String, in block: String) -> Bool? {
    blenderFirstMatch("\"\(key)\"\\s*:\\s*(True|False)", in: block).map { $0 == "True" }
}

private func blenderFirstMatch(_ pattern: String, in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range),
          match.numberOfRanges > 1,
          let matchRange = Range(match.range(at: 1), in: text)
    else { return nil }
    return String(text[matchRange])
}
