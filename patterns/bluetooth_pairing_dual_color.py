"""bluetooth_pairing_dual_color — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Blue + white dots, no trails.")


def schedule_bluetooth_pairing_dual_color(controller, system):
    """Blue dot (Color0, CW) + white dot (Color1, CCW), no trails (2-color limit)."""
    controller.add_event_at_time_ms(0, set_color0, system, *COLOR_BLUE)
    controller.add_event_at_time_ms(0, set_color1, system, *COLOR_WHITE)
    controller.add_event_at_time_ms(0, set_fade_rate, system, 2)
    controller.add_event_at_time_ms(0, global_off, system)
    rotation_ms = 1700
    num_rotations = 3
    ms_per_led = max(50, (rotation_ms // TOTAL_LEDS) // 50 * 50)
    start_cw, start_ccw = 0, TOTAL_LEDS - 1
    total_steps = num_rotations * TOTAL_LEDS
    for step in range(total_steps):
        t = step * ms_per_led
        curr_cw = (start_cw + step) % TOTAL_LEDS
        curr_ccw = (start_ccw - step) % TOTAL_LEDS
        if step > 0:
            prev_cw = (start_cw + step - 1) % TOTAL_LEDS
            prev_ccw = (start_ccw - step + 1) % TOTAL_LEDS
            is_crossover = (prev_cw == curr_ccw) or (prev_ccw == curr_cw)
            if not is_crossover:
                controller.add_event_at_time_ms(t, select_led, system, prev_cw, False, 0x00)
                controller.add_event_at_time_ms(t, select_led, system, prev_ccw, False, 0x00)
        controller.add_event_at_time_ms(t, select_led, system, curr_cw, True, 0x00)
        controller.add_event_at_time_ms(t, select_led, system, curr_ccw, True, 0x07)
    final_time_ms = total_steps * ms_per_led
    final_cw = (start_cw + total_steps - 1) % TOTAL_LEDS
    final_ccw = (start_ccw - total_steps + 1) % TOTAL_LEDS
    controller.add_event_at_time_ms(final_time_ms, select_led, system, final_cw, False, 0x00)
    controller.add_event_at_time_ms(final_time_ms, select_led, system, final_ccw, False, 0x00)
    return final_time_ms + 1000
