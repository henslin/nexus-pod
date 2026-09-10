"""spotlight_deterrence — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("White presence -> amber -> dark break -> red triple-burst alarm.")


def schedule_spotlight_deterrence(controller, system):
    """Spotlight Deterrence: a calm, deliberate "you are being recorded" cue (NO fast
    strobe). 7 phases: OFF -> white spotlight rise+hold -> slow crossfade to a red-amber
    deterrence color -> steady hold -> dark break -> saturated red triple-burst alarm ->
    off. TWO COLORS ONLY, time-sliced on Color1 (white -> deterrence -> red) with Color0
    pinned to black; ONE global fade rate at a time, each rate change scheduled PREP=100ms
    before its edge while the ring is steady."""
    off_ms = 500
    white_rgb = (180, 180, 180)
    white_fade_rate = 3
    white_hold_ms = 3500
    deterrence_rgb = (180, 35, 0)
    ramp_fade_rate = 5
    ramp_ms = 2500
    steady_hold_ms = 4500
    breathe = False
    breathe_period_ms = 5000
    breathe_dim_frac = 0.6
    breathe_rise_rate = 6
    breathe_fall_rate = 4
    breathe_cycles = 2
    fade_out_at_end = False
    end_fade_rate = 5
    end_fade_ms = 2000
    end_dark_ms = 500
    end_pad_ms = 500
    alarm = True
    break_ms = 3500
    break_off_fade_rate = 3
    alarm_red_rgb = (220, 0, 0)
    alarm_fade_rate = 0
    burst_flash_on_ms = 110
    burst_flash_off_ms = 180
    burst_count = 3
    burst_gap_ms = 800
    alarm_cycles = 4

    PREP = 100

    if breathe and breathe_period_ms < 4000:
        breathe_period_ms = 4000

    t_white_on = off_ms
    t_ramp = t_white_on + white_hold_ms
    t_steady = t_ramp + ramp_ms
    if breathe:
        n_cycles = max(1, int(breathe_cycles))
        presence_ms = n_cycles * breathe_period_ms
    else:
        n_cycles = 0
        presence_ms = steady_hold_ms
    t_presence_end = t_steady + presence_ms

    alarm_cycle_ms = burst_count * (burst_flash_on_ms + burst_flash_off_ms) + burst_gap_ms
    t_break_start = t_presence_end
    t_alarm_start = t_break_start + break_ms
    t_alarm_end = t_alarm_start + alarm_cycles * alarm_cycle_ms

    if alarm:
        total_ms = t_alarm_end + end_pad_ms
    elif fade_out_at_end:
        total_ms = t_presence_end + end_fade_ms + end_dark_ms
    else:
        total_ms = t_presence_end + end_pad_ms

    wr, wg, wb = white_rgb
    dr, dg, db = deterrence_rgb

    controller.add_event_at_time_ms(0, set_color0, system, 0, 0, 0)
    controller.add_event_at_time_ms(0, global_off, system)

    controller.add_event_at_time_ms(max(0, t_white_on - PREP), set_fade_rate, system, white_fade_rate)
    controller.add_event_at_time_ms(max(0, t_white_on - PREP), set_color1, system, wr, wg, wb)
    controller.add_event_at_time_ms(t_white_on, select_all_leds, system, True, 0x07)

    controller.add_event_at_time_ms(t_ramp - PREP, set_fade_rate, system, ramp_fade_rate)
    controller.add_event_at_time_ms(t_ramp, set_color1, system, dr, dg, db)

    if breathe:
        ddr = int(dr * breathe_dim_frac)
        ddg = int(dg * breathe_dim_frac)
        ddb = int(db * breathe_dim_frac)
        half = breathe_period_ms // 2
        for c in range(n_cycles):
            c0 = t_steady + c * breathe_period_ms
            controller.add_event_at_time_ms(max(0, c0 - PREP), set_fade_rate, system, breathe_fall_rate)
            controller.add_event_at_time_ms(c0, set_color1, system, ddr, ddg, ddb)
            controller.add_event_at_time_ms(c0 + half - PREP, set_fade_rate, system, breathe_rise_rate)
            controller.add_event_at_time_ms(c0 + half, set_color1, system, dr, dg, db)

    if alarm:
        controller.add_event_at_time_ms(t_break_start - PREP, set_fade_rate, system, break_off_fade_rate)
        controller.add_event_at_time_ms(t_break_start, select_all_leds, system, False, 0x00)

        ar, ag, ab = alarm_red_rgb
        controller.add_event_at_time_ms(t_alarm_start - PREP, set_color1, system, ar, ag, ab)
        controller.add_event_at_time_ms(t_alarm_start - PREP, set_fade_rate, system, alarm_fade_rate)
        flash_period = burst_flash_on_ms + burst_flash_off_ms
        for cyc in range(alarm_cycles):
            cyc0 = t_alarm_start + cyc * alarm_cycle_ms
            for b in range(burst_count):
                on_t = cyc0 + b * flash_period
                controller.add_event_at_time_ms(on_t, select_all_leds, system, True, 0x07)
                controller.add_event_at_time_ms(on_t + burst_flash_on_ms, select_all_leds, system, True, 0x00)
        controller.add_event_at_time_ms(t_alarm_end, global_off, system)
    elif fade_out_at_end:
        controller.add_event_at_time_ms(t_presence_end - PREP, set_fade_rate, system, end_fade_rate)
        controller.add_event_at_time_ms(t_presence_end, select_all_leds, system, True, 0x00)
        controller.add_event_at_time_ms(t_presence_end + end_fade_ms, global_off, system)

    return total_ms


# ============================================================================
# EYE-CANDY ONBOARDING PATTERNS
# ----------------------------------------------------------------------------
# Every one produces its rich multi-hue look ENTIRELY through the hardware fade
# engine driven by the 2-color Frozen API: exactly two palette colors at any
# instant (Color0/Color1), ONE global fade rate set at t=0 (rise/fall asymmetry
# is the "trail"), per-LED variety via staggered 0x07/0x00 selection flips, and
# global "shimmer/breath" via periodic set_color0/set_color1 palette rewrites.
# No per-LED RGB is ever written, so every recorded frame passes the 2-color gate.
#
# The two noise-driven patterns (perlin_noise_flicker, plasma_drift) originally
# sampled Blender's mathutils.noise.noise(); since schedulers must run headless,
# that is replaced by _perlin_noise_3d(), a deterministic pure-Python classic
# Ken-Perlin improved-noise implementation (~[-1,1]). Determinism was prioritized
# over byte-matching Blender's exact field.
# ============================================================================
