"""device_offline — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = 10850
RENDER_ONLY = False
DESCRIPTION = ("Fade off then amber/red alternating.")


def schedule_device_offline(controller, system):
    """MEDIUM fade-off (350 ms), then amber/red alternating IMMEDIATE 500/500
    (firmware: 3 steps — a one-time off lead-in + the 2-frame alt the renderer
    repeats to fill ~10.85 s)."""
    # Lead-in: all-off at MEDIUM for 350 ms.
    controller.add_event_at_time_ms(0, set_color0, system, 0, 0, 0)
    controller.add_event_at_time_ms(0, set_color1, system, 0, 0, 0)
    controller.add_event_at_time_ms(0, set_fade_rate, system, 4)  # MEDIUM
    controller.add_event_at_time_ms(0, select_all_leds, system, True, 0x07)
    # Amber then red, IMMEDIATE, 500 ms each.
    controller.add_event_at_time_ms(350, set_color1, system, *COLOR_AMBER)
    controller.add_event_at_time_ms(350, set_fade_rate, system, 0)  # IMMEDIATE
    controller.add_event_at_time_ms(350, select_all_leds, system, True, 0x07)
    controller.add_event_at_time_ms(850, set_color1, system, *COLOR_RED)
    controller.add_event_at_time_ms(850, set_fade_rate, system, 0)
    controller.add_event_at_time_ms(850, select_all_leds, system, True, 0x07)
    return 1350
