"""booting_up — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = 5 * 6000
RENDER_ONLY = False
DESCRIPTION = ("All LEDs breathe white, 3 cycles.")


def schedule_booting_up(controller, system):
    """White breathing (firmware: 2-step cycle, SLOW ~2s fade, renderer repeats
    5x over 30s). One cycle = all-white 3s then all-off 3s, both SLOW."""
    controller.add_event_at_time_ms(0, set_color0, system, 0, 0, 0)
    controller.add_event_at_time_ms(0, set_color1, system, *COLOR_WHITE)
    controller.add_event_at_time_ms(0, set_fade_rate, system, 6)  # SLOW
    controller.add_event_at_time_ms(0, select_all_leds, system, True, 0x07)
    controller.add_event_at_time_ms(3000, select_all_leds, system, True, 0x00)
    return 6000  # one cycle; DURATION_MS macro loops it (5 * 6000)
