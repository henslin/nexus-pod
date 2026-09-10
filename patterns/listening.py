"""listening — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Voice-assistant listening feedback (blue water + white glimmers).")


def schedule_listening(controller, system):
    """Ziris "Listening" — voice-assistant listening feedback: calm blue water
    with occasional soft white glimmers. A re-tuning of the blue->white ripple
    engine (NOT new motion): fewer/slower/gentler fronts from a listening-specific
    seed. 12 s seamless loop keyed every 100 ms.

    2-color + fade-engine hue approach: Color0 = electric blue floor (ring never
    deselects), Color1 = white glimmer, set once at t=0 with one global fade rate.
    Per tick, per LED, raw = drop_brightness(i,t)/norm_max is quantized to a single
    selection bit (0x07 white if raw >= threshold, else 0x00 blue), delta-filtered.

    Portability note: the tuned motion params (n_drops/ripple_speed/decay_rate/
    pulse_w) require the extended ripple.py the ziris runtime shipped. If the
    ripple.py on the path has the narrower reference signature, we fall back to
    the seed-only retuning (make_drops(seed)) so the pattern still runs — the
    motion is close but not identically tuned."""
    _ripple = _import_ripple_math()
    color0_rgb = (40, 120, 255)     # electric blue floor
    color1_rgb = (255, 255, 255)    # white glimmer
    threshold = 0.45
    fade_rate_idx = 4
    loop_seconds = 12.0
    tick_ms = 100
    n_drops = 9
    ripple_speed = 4.0
    decay_rate = 0.55
    pulse_w = 0.9
    seed = 7

    if _ripple.NUM_LEDS != TOTAL_LEDS:
        raise RuntimeError(
            f"ripple.py NUM_LEDS={_ripple.NUM_LEDS} != ring TOTAL_LEDS={TOTAL_LEDS}")

    if _ripple_supports_tuning(_ripple):
        drops = _ripple.make_drops(seed, n_drops=n_drops)
        norm_max = _ripple.normalization_max(
            drops, ripple_speed=ripple_speed, decay_rate=decay_rate, pulse_w=pulse_w)

        def raw_at(i, t_s):
            return _ripple.drop_brightness(
                i, t_s, drops, ripple_speed=ripple_speed,
                decay_rate=decay_rate, pulse_w=pulse_w) / norm_max
    else:
        # Narrow reference signature: retune via the seed only.
        drops = _ripple.make_drops(seed)
        norm_max = _ripple.normalization_max(drops)

        def raw_at(i, t_s):
            return _ripple.drop_brightness(i, t_s, drops) / norm_max

    loop_ms = int(loop_seconds * 1000)
    controller.add_event_at_time_ms(0, set_color0, system, *color0_rgb)
    controller.add_event_at_time_ms(0, set_color1, system, *color1_rgb)
    controller.add_event_at_time_ms(0, set_fade_rate, system, fade_rate_idx)
    controller.add_event_at_time_ms(0, select_all_leds, system, True, 0x00)

    last_states = [0x00] * TOTAL_LEDS
    t_ms = tick_ms
    while t_ms < loop_ms:
        t_s = t_ms / 1000.0
        for i in range(TOTAL_LEDS):
            new_bits = 0x07 if raw_at(i, t_s) >= threshold else 0x00
            if new_bits != last_states[i]:
                controller.add_event_at_time_ms(t_ms, select_led, system, i, True, new_bits)
                last_states[i] = new_bits
        t_ms += tick_ms
    return loop_ms


# ============================================================================
# ARM AWAY / ARM HOME (spin -> solid -> fade)
# ============================================================================
