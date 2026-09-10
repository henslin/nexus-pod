"""firmware_update — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Amber/blue vertical fill.")


def schedule_firmware_update(controller, system):
    """Two-color spin: AMBER dot clockwise + BLUE dot counter-clockwise, one
    rotation, FAST, 312 ms/frame. Byte-matches firmware firmware_update
    (16x SPIN_FRAME_2C(cw, ccw, (RGB_AMBER), (RGB_BLUE)))."""
    controller.add_event_at_time_ms(0, set_color0, system, *COLOR_AMBER)  # CW dot
    controller.add_event_at_time_ms(0, set_color1, system, *COLOR_BLUE)   # CCW dot
    controller.add_event_at_time_ms(0, set_fade_rate, system, 2)          # FAST
    controller.add_event_at_time_ms(0, global_off, system)
    frame_ms = 312  # exact firmware frame; recorder honors it
    t = 0
    for k in range(TOTAL_LEDS):
        cw, ccw = k, (TOTAL_LEDS - 1 - k) % TOTAL_LEDS
        controller.add_event_at_time_ms(t, select_all_leds, system, False, 0x00)
        controller.add_event_at_time_ms(t, select_led, system, cw, True, 0x00)   # amber
        controller.add_event_at_time_ms(t, select_led, system, ccw, True, 0x07)  # blue
        t += frame_ms
    return t
