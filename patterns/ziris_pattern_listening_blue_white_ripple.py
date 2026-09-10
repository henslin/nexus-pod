"""
ziris_pattern_listening_blue_white_ripple.py -- Ziris "Listening" (blue &
white ripple) handoff extract.

Standalone copy of pattern_listening() -- the voice-assistant listening
feedback state: calm electric-blue water with white glimmer cores.

Source of truth: blender_ziris_led_integration_emissive.py, in the sibling
"blender 3D CAD file/" folder (canonical copy at
Python_LED_Animations_Organized/Phase5_.../Ziris/White-Blue-Green-Amber-Ice-
Tidepool-Red-Rainbow/blender_ziris_led_integration_emissive.py). This file is
a HANDOFF EXTRACT for review / build -- it is not a fork. If the pattern
needs changes, either edit it here and re-paste into the source file once
approved, or edit the source file and re-copy here; don't let the two
diverge silently.

This is a RE-TUNING of the existing Ripple effect, NOT new motion and NOT a
new palette. The motion math is imported verbatim from ripple.py (copied
alongside this file in BOD/):
  - make_drops(seed, n_drops)        -> deterministic (t_land, center) drop table
  - drop_brightness(i, t, ..)        -> summed expanding-Gaussian fronts + seam wrap
  - normalization_max(drops, ..)     -> peak used to normalize raw -> [0..1]
ripple.py's own baked module constants (N_DROPS=8, RIPPLE_SPEED=5.5,
DECAY_RATE=0.65, PULSE_W=1.1, SEED=42) are NOT modified by this pattern, so
pattern_ripple (the original effect) renders bit-identically; the
listening-tuned values below are passed through ripple.py's backward-
compatible kwargs instead.

Requirements: run inside Blender with Arlo_Ziris.blend open (LED1..LED16
single-mesh emission driver outputs present). Needs the "blender 3D CAD
file/" folder (sibling of the *source* file's parent) on sys.path for the
shared simulator + integration modules -- do not edit those from here; see
CLAUDE.md in that folder for the hardware-accuracy contract this pattern
obeys.

Known issue (not specific to this pattern, inherited from the source file):
on Blender 5.1.2, baking keyframes onto multiple split per-LED node-trees in
one script pass can collapse most of them onto one shared Action/slot, so
LEDs 2-16 may mirror LED 2's animation instead of their own when previewed.
This is tracked as a separate fix to bake_animation_to_keyframes() in the
source file; this pattern's own selection logic is correct independent of
that baking bug.
"""

import math
import os
import sys

import bpy

_INTEGRATION_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "blender 3D CAD file",
)
if _INTEGRATION_DIR not in sys.path:
    sys.path.insert(0, _INTEGRATION_DIR)

# Frozen API + constants (set_color0, set_color1, set_fade_rate, select_led,
# select_all_leds, FADE_RATES, TOTAL_LEDS, ...) -- read-only per CLAUDE.md.
from ktd2064_blender_simulator import *  # noqa: F401,F403

# Shared integration-layer plumbing this pattern depends on. Defined in the
# main integration file; imported rather than duplicated here.
from blender_ziris_led_integration_emissive import (
    setup_pattern_common,
    finalize_pattern,
    ensure_per_led_materials,
    _stash_existing_led_animation,
)


def pattern_listening(
    color0_rgb=(40, 120, 255),       # electric blue floor (Color0) -- luminous, awake
    color1_rgb=(255, 255, 255),      # white glimmer  (Color1) -- unchanged
    white_core_threshold=0.45,       # more LEDs cross into Color1 white, for longer -> more white spots
    fade_rate_idx=4,                 # slightly slower tau than ripple's 3 -> more liquid / serene wake
    emission_strength=1000.0,
    loop_seconds=12.0,               # keep the seamless 12.0 s loop
    tick_ms=100,                     # 2x the 50 ms firmware tick, as in pattern_ripple
    # --- listening-specific MOTION ---
    n_drops=9,                       # more fronts overlap -> more simultaneous peaks -> more white spots
    ripple_speed=4.0,                # slower fronts than ripple's 5.5 -> serene, water-like
    decay_rate=0.55,                 # gentler fade than ripple's 0.65 -> softer, longer laps
    pulse_w=0.9,                     # tighter front than ripple's 1.1 -> crisp white points, not a wash
    seed=7,                          # listening-specific drop table (distinct from ripple's 42)
    split_shared_materials=True,     # Ziris shares one LED material -> split so per-LED renders
    preserve_existing=True,
    debug=False,
):
    """
    "Listening" (blue & white) -- voice-assistant listening feedback, KTD2064-accurate.

    This is a RE-TUNING of the existing Ripple effect, NOT new motion and NOT a
    new palette. The motion math is imported verbatim from ../ripple.py:
      - make_drops(seed, n_drops)  -> deterministic (t_land, center) drop table
      - drop_brightness(i, t, ..)  -> summed expanding-Gaussian fronts + seam wrap
      - normalization_max(drops, ..) -> peak used to normalize raw -> [0..1]
    Unlike pattern_ripple, which uses ripple.py's baked module constants, this
    pattern passes listening-tuned motion parameters through the same functions'
    backward-compatible kwargs (n_drops / ripple_speed / decay_rate / pulse_w).
    ripple.py's baked constants (N_DROPS=8, RIPPLE_SPEED=5.5, DECAY_RATE=0.65,
    PULSE_W=1.1, SEED=42) are NOT modified, so pattern_ripple renders
    bit-identically.

    Per tick, per LED, the normalized level `raw = drop_brightness(i,t)/NORM_MAX`
    is quantized to a selection bit (Color1 white if raw >= white_core_threshold,
    else Color0 blue). The ring never deselects, so the electric-blue floor is
    always lit ("device is awake and attentive"). The single global fade engine
    renders the analog crossfade as fronts sweep -- and the blue -> white transit
    passes through light blue, giving the dim -> mid -> core hue ramp from 2
    registers. A LOWER white_core_threshold + more drops (9) + a tighter front
    (pulse_w=0.9) means more crisp white spots appear around the ring, more
    often, without smearing into a white wash. There is no third register.

    HARDWARE CAVEATS (honest limits of the 2-register + global-fade chip):
      1. No per-LED brightness: the dim floor + bright glimmer is realized as a
         HUE shift (blue field -> white cores) plus the modest strength
         difference between the palettes, not a per-LED dimmer. Same trade every
         pattern in this file makes.
      2. Rise/fall asymmetry is real (rise ~0.5*tau, fall ~4-6*tau). Here it is a
         FEATURE: the slow fall leaves an expanding ripple "wake" trailing each
         front, which reads as calm water rippling and settling.

    Args:
        color0_rgb: dim-floor palette (Color0). Default electric blue (40,120,255)
            -- more luminous and awake than pattern_ripple's deep blue.
        color1_rgb: hot-core palette (Color1). Default white (255,255,255).
        white_core_threshold: normalized level (0..1) at/above which a LED selects
            Color1 (white). Default 0.45 -> the primary "more white" lever: more
            LEDs cross into white, and for longer. Nudge up toward 0.50 if the
            ring reads too busy; down toward 0.40 for more white.
        fade_rate_idx: 0-7 global fade index. Default 4 (500 ms tau) vs ripple's 3
            -> more liquid, serene motion.
        emission_strength: Cycles emission multiplier. Default 1000. Scene boosts
            stack via _compute_emission_strength().
        loop_seconds: seamless loop length. Default 12.0. The timeline is set to
            exactly one loop so the rendered clip is one seamless cycle.
        tick_ms: selection decision cadence in ms. Default 100 (a multiple of the
            50 ms firmware tick), matching pattern_ripple's 100 ms keying.
        n_drops: drops per loop. Default 9 (vs ripple's 8) -> more overlapping
            fronts -> more simultaneous peaks -> more white spots at once.
        ripple_speed: ring positions/second traveled by the front. Default 4.0
            (vs ripple's 5.5) -> slower, water-like fronts.
        decay_rate: exponential amplitude decay per second. Default 0.55 (vs
            ripple's 0.65) -> softer, longer laps. NORM_MAX is recomputed for the
            resulting motion so the normalization always matches.
        pulse_w: Gaussian front width in LED units. Default 0.9 (vs ripple.py's
            PULSE_W=1.1) -> tighter fronts so the extra white reads as distinct
            crisp points, not a white smear. Passed through to drop_brightness /
            normalization_max; ripple.py's PULSE_W constant is untouched.
        seed: RNG seed for drop placement. Default 7 (distinct from ripple's 42)
            -> a listening-specific drop table.
        split_shared_materials: True (default) -> if the LEDs share one material
            (Arlo_Ziris.blend does), give each a single-user copy so per-LED
            animation renders. No-op when LEDs already have unique materials.
        preserve_existing: True -> stash existing LED actions before bake.
        debug: unused; signature parity with the other pattern_*() functions.

    Returns:
        (system, controller) tuple, or (None, None) on failure.
    """
    import importlib

    # --- Import the CANONICAL ripple math. Reuse, don't rewrite. ---
    # In the source file this looks near SCRIPT_DIR (LED project root); here we
    # look next to this extract first (BOD/ripple.py), matching where this
    # handoff copy of ripple.py was placed.
    _ripple = None
    _this_dir = os.path.dirname(os.path.abspath(__file__))
    _cands = [
        _this_dir,                                       # alongside this extract (BOD/)
        os.path.dirname(_INTEGRATION_DIR),               # LED/  (parent of "blender 3D CAD file")
    ]
    for _cand in _cands:
        if _cand and os.path.isfile(os.path.join(_cand, "ripple.py")):
            if _cand not in sys.path:
                sys.path.insert(0, _cand)
            import ripple as _ripple
            importlib.reload(_ripple)
            break
    if _ripple is None:
        print("  ERROR: pattern_listening could not find ripple.py (the canonical "
              "motion math). Looked in:")
        for _cand in _cands:
            print(f"    - {_cand}")
        print("  Place ripple.py alongside this extract and re-run.")
        return None, None

    if _ripple.NUM_LEDS != TOTAL_LEDS:
        print(f"  ERROR: ripple.py NUM_LEDS={_ripple.NUM_LEDS} but this ring has "
              f"TOTAL_LEDS={TOTAL_LEDS}. Ripple motion assumes a {TOTAL_LEDS}-LED "
              f"ring; aborting rather than baking a mismatched pattern.")
        return None, None

    threshold = white_core_threshold

    # Listening-tuned motion via ripple.py's backward-compatible kwargs. The
    # baked module constants (N_DROPS/RIPPLE_SPEED/DECAY_RATE/PULSE_W/SEED) are
    # NOT touched, so pattern_ripple is unaffected. NORM_MAX must be computed
    # with the SAME motion params it will normalize, so ripple_speed/decay_rate/
    # pulse_w/n_drops all flow into make_drops + normalization_max here (and into
    # every drop_brightness() call in the tick loop below).
    drops = _ripple.make_drops(seed, n_drops=n_drops)
    norm_max = _ripple.normalization_max(drops, ripple_speed=ripple_speed,
                                         decay_rate=decay_rate, pulse_w=pulse_w)

    print(f"=== Pattern: Listening (blue & white) ===")
    print(f"  motion (ripple.py, listening-tuned): n_drops={n_drops} "
          f"(baked N_DROPS={_ripple.N_DROPS}), ripple_speed={ripple_speed} "
          f"(baked {_ripple.RIPPLE_SPEED}), decay_rate={decay_rate} "
          f"(baked {_ripple.DECAY_RATE}), pulse_w={pulse_w} "
          f"(baked PULSE_W={_ripple.PULSE_W}), RIPPLE_LIFE={_ripple.RIPPLE_LIFE}, "
          f"FLOOR={_ripple.FLOOR}, SEED={seed}")
    print(f"  NORM_MAX = {norm_max:.3f} (ambient seed-42 baked value: 1.527)")
    print(f"  Color0 (electric-blue floor) = {color0_rgb}")
    print(f"  Color1 (white glimmer)       = {color1_rgb}")
    print(f"  white_core_threshold = {threshold} (>= -> Color1 white; lower = more white spots)")
    print(f"  fade_rate_idx = {fade_rate_idx} (tau = {FADE_RATES[fade_rate_idx]} ms)")
    print(f"  loop_seconds = {loop_seconds}, tick_ms = {tick_ms}")

    # Timeline = exactly one loop so the clip is one seamless cycle.
    fps = bpy.context.scene.render.fps
    timeline_total_seconds = loop_seconds
    total_ms = timeline_total_seconds * 1000.0
    loop_ms = loop_seconds * 1000.0

    system, controller, led_groups = setup_pattern_common(
        duration_seconds=timeline_total_seconds, fps=fps,
        emission_strength=emission_strength,
    )
    if system is None:
        return None, None

    # Per-LED effect REQUIRES per-LED materials. Ziris ships a single shared
    # "Emissive" material across all 16 LEDs; without this split every LED would
    # render identically. Mutates led_groups in place; sync system's copy.
    if split_shared_materials:
        ensure_per_led_materials(led_groups)
        system.blender_led_groups = led_groups

    stash_ts = None
    if preserve_existing:
        stash_ts = _stash_existing_led_animation(led_groups, "PrevPattern")

    # --- t=0 initial state: palette + fade rate + select_all_leds(True, 0x00) ---
    # Ring starts on the deep-blue floor and never deselects, so the floor glow
    # is always present. t=0 is a quiet moment (all Color0), which also matches
    # the loop-end selection state -> no selection pop at the seam.
    c0_r, c0_g, c0_b = color0_rgb
    c1_r, c1_g, c1_b = color1_rgb
    controller.add_event_at_time_ms(0, set_color0, system, c0_r, c0_g, c0_b)
    controller.add_event_at_time_ms(0, set_color1, system, c1_r, c1_g, c1_b)
    controller.add_event_at_time_ms(0, set_fade_rate, system, fade_rate_idx)
    controller.add_event_at_time_ms(0, select_all_leds, system, True, 0x00)

    # --- Build the per-LED selection schedule for one loop -------------------
    # For each tick, quantize the canonical ripple level to a Color0/Color1 bit;
    # emit select_led only on change (delta filter, like aurora/plasma). The
    # listening motion params (ripple_speed/decay_rate/pulse_w) are threaded into
    # every drop_brightness() call so the schedule matches the norm computed above.
    last_states = [0x00] * TOTAL_LEDS   # matches select_all_leds(True, 0x00) at t=0
    events_one_loop = []
    t_ms = tick_ms                      # t=0 already covered by select_all above
    while t_ms < loop_ms:
        t_s = t_ms / 1000.0
        for i in range(TOTAL_LEDS):
            raw = _ripple.drop_brightness(i, t_s, drops,
                                          ripple_speed=ripple_speed,
                                          decay_rate=decay_rate,
                                          pulse_w=pulse_w) / norm_max
            new_bits = 0x07 if raw >= threshold else 0x00
            if new_bits != last_states[i]:
                events_one_loop.append((t_ms, i, new_bits))
                last_states[i] = new_bits
        t_ms += tick_ms

    # --- Tile across the timeline (loop closure guaranteed by drop-phase wrap) ---
    num_loops = int(math.ceil(total_ms / loop_ms))
    for loop_i in range(num_loops):
        base_ms = loop_i * loop_ms
        for (t_ms_local, led_idx, bits) in events_one_loop:
            actual = base_ms + t_ms_local
            if actual <= total_ms:
                controller.add_event_at_time_ms(
                    int(actual), select_led, system, led_idx, True, bits)

    # --- Pre-finalize checklist (CLAUDE.md) ---
    # 1. Frozen API only? OK -- set_color0/1, set_fade_rate, select_all_leds, select_led.
    # 2. One global fade rate? OK -- set once at t=0, never changed.
    # 3. Per-LED diffs via selection bits only? OK -- 0x07 (white glimmer) vs 0x00
    #    (blue floor); palette RGB is never overridden per LED.
    # 4. Events >= 50 ms apart? OK -- tick_ms=100 (2 firmware ticks).
    # 5. Simulator untouched? OK -- ripple.py is imported read-only (and its baked
    #    constants are unchanged; only its backward-compatible kwargs are used).
    #    Only the Frozen API is called.
    # 6. Asymmetric rise/fall acceptable? OK -- documented as the ripple "wake"
    #    (slow fall = trailing edge of the spreading front; reads as calm water).
    # 7. Describable as ktd2064_* calls? OK -- a stream of ktd2064_select_led()
    #    flips over a fixed Color0/Color1 palette, pre-baked from the offline
    #    ripple math.

    finalize_pattern(system, controller, led_groups, total_ms, "Listening")

    # Rename newly-created actions for easy identification.
    if stash_ts:
        for led_idx in range(TOTAL_LEDS):
            if led_idx >= len(led_groups) or not led_groups[led_idx]:
                continue
            for obj, shader_node, node_type in led_groups[led_idx]:
                if not (obj.active_material and obj.active_material.use_nodes):
                    continue
                nt = obj.active_material.node_tree
                if nt.animation_data and nt.animation_data.action:
                    a = nt.animation_data.action
                    if not a.name.startswith("Listening_"):
                        led_num = led_idx + 1
                        a.name = f"Listening_LED{led_num}_{stash_ts}"

    print(f"\n[Listening] complete.")
    print(f"  Selection-bit transitions per loop: {len(events_one_loop)}")
    if stash_ts:
        print(f"  Stash prefix:  PrevPattern_{stash_ts}_*")
        print(f"  New actions:   Listening_LEDx_{stash_ts}")
    return system, controller


# RUN (commented out -- never auto-run; see CLAUDE.md "never render" rule)
# if __name__ == "__main__":
#     system, controller = pattern_listening()
