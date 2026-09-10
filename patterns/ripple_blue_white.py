"""ripple_blue_white — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Blue->white raindrop ripple (hue crossfade via fade engine).")


def schedule_ripple_blue_white(controller, system):
    """Ziris "Raindrop Ripple" — the blue->white ripple (distinct from the
    firmware's green snapshot ripple, schedule_ripple_green). Drops land at
    random ring positions and ripple symmetrically outward, fading as they
    spread; ripples overlap, no spin. 12 s seamless loop keyed every 100 ms.

    2-color + fade-engine hue approach: Color0 = deep blue (dim floor, ring
    never deselects), Color1 = white (hot core), set once at t=0 with one global
    fade rate. Per tick, per LED, the canonical ripple level
    raw = drop_brightness(i,t)/norm_max is quantized to a single selection bit
    (0x07 white if raw >= WHITE_START, else 0x00 blue), delta-filtered so
    select_led is emitted only on change. The fade engine paints the
    deep-blue -> light-blue -> white crossfade from just two registers."""
    _ripple = _import_ripple_math()
    color0_rgb = (20, 70, 190)
    color1_rgb = (255, 255, 255)
    fade_rate_idx = 3
    loop_seconds = 12.0
    tick_ms = 100
    seed = _ripple.SEED
    threshold = _ripple.WHITE_START

    if _ripple.NUM_LEDS != TOTAL_LEDS:
        raise RuntimeError(
            f"ripple.py NUM_LEDS={_ripple.NUM_LEDS} != ring TOTAL_LEDS={TOTAL_LEDS}")

    drops = _ripple.make_drops(seed)
    norm_max = _ripple.normalization_max(drops)
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
            raw = _ripple.drop_brightness(i, t_s, drops) / norm_max
            new_bits = 0x07 if raw >= threshold else 0x00
            if new_bits != last_states[i]:
                controller.add_event_at_time_ms(t_ms, select_led, system, i, True, new_bits)
                last_states[i] = new_bits
        t_ms += tick_ms
    return loop_ms
