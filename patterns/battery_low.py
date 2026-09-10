"""battery_low — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = 5500
RENDER_ONLY = False
DESCRIPTION = ("Top 2 LEDs blink amber.")


def schedule_battery_low(controller, system):
    """Top 2 LEDs (0, 15) blink amber 300/300 (firmware: 2-step cycle,
    IMMEDIATE, renderer repeats over 5.5s)."""
    return _schedule_blink_cycle(controller, system, COLOR_AMBER,
                                 on_ms=300, off_ms=300, led_indices=TOP_LEDS)
