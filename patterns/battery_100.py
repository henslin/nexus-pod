"""battery_100 — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = 16000
RENDER_ONLY = False
DESCRIPTION = ("Full-ring white cascade, hold solid.")


def schedule_battery_100(controller, system):
    """Full-ring white cascade (MEDIUM/500 ms), hold all-on 5 s, then fade off
    1 s. NOTE: the firmware splits the 16th cascade frame (500 ms) and the hold
    (5000 ms) into two identical all-on steps (18 total); the command recorder
    coalesces identical consecutive snapshots, so this records as one 5500 ms
    all-on frame (17 steps). Visually identical on device; not byte-identical to
    the firmware's cosmetic split. See test_firmware_parity IDIOM_ONLY."""
    controller.add_event_at_time_ms(0, set_color0, system, 0, 0, 0)
    controller.add_event_at_time_ms(0, set_color1, system, *COLOR_WHITE)
    controller.add_event_at_time_ms(0, set_fade_rate, system, 4)  # MEDIUM
    controller.add_event_at_time_ms(0, global_off, system)
    for i in range(TOTAL_LEDS):
        controller.add_event_at_time_ms(i * 500, select_led, system, i, True, 0x07)
    hold_end = TOTAL_LEDS * 500 + 5000  # all-on held through the hold window
    controller.add_event_at_time_ms(hold_end, select_all_leds, system, True, 0x00)
    return hold_end + 1000
