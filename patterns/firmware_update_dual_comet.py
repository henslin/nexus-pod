"""firmware_update_dual_comet — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Blue CW + amber CCW dots.")


def schedule_firmware_update_dual_comet(controller, system):
    """Firmware Update (dual-comet): a BLUE dot spins clockwise from the top-right
    (index 0) while an AMBER dot spins counter-clockwise from the top-left (index 15),
    for 3 full rotations. 2-color palette (Color0=blue, Color1=amber) set once; each
    comet is a single selected LED (blue via 0x00, amber via 0x07) with the global fade
    engine (rate 2) giving a short trail. Single dots (no gradient trails) — KTD2064 has
    only Color0/Color1."""
    rotation_ms = 3000
    num_rotations = 3
    fade_rate = 2

    controller.add_event_at_time_ms(0, set_color0, system, *COLOR_BLUE)
    controller.add_event_at_time_ms(0, set_color1, system, *COLOR_AMBER)
    controller.add_event_at_time_ms(0, set_fade_rate, system, fade_rate)
    controller.add_event_at_time_ms(0, global_off, system)

    ms_per_led = max(50, (rotation_ms // TOTAL_LEDS) // 50 * 50)
    start_cw, start_ccw = 0, TOTAL_LEDS - 1
    total_steps = num_rotations * TOTAL_LEDS

    for step in range(total_steps):
        time_ms = step * ms_per_led
        curr_cw = (start_cw + step) % TOTAL_LEDS
        curr_ccw = (start_ccw - step) % TOTAL_LEDS
        if step > 0:
            prev_cw = (start_cw + step - 1) % TOTAL_LEDS
            prev_ccw = (start_ccw - step + 1) % TOTAL_LEDS
            is_crossover = (prev_cw == curr_ccw) or (prev_ccw == curr_cw)
            if not is_crossover:
                controller.add_event_at_time_ms(time_ms, select_led, system, prev_cw, False, 0x00)
                controller.add_event_at_time_ms(time_ms, select_led, system, prev_ccw, False, 0x00)
        controller.add_event_at_time_ms(time_ms, select_led, system, curr_cw, True, 0x00)
        controller.add_event_at_time_ms(time_ms, select_led, system, curr_ccw, True, 0x07)

    final_time_ms = total_steps * ms_per_led
    final_cw = (start_cw + total_steps - 1) % TOTAL_LEDS
    final_ccw = (start_ccw - total_steps + 1) % TOTAL_LEDS
    controller.add_event_at_time_ms(final_time_ms, select_led, system, final_cw, False, 0x00)
    controller.add_event_at_time_ms(final_time_ms, select_led, system, final_ccw, False, 0x00)
    return final_time_ms + 1000
