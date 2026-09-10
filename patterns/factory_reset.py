"""factory_reset — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("All LEDs blink amber ~1 Hz.")


def schedule_factory_reset(controller, system):
    """All 16 LEDs blink amber at 1 Hz, 500/500 (firmware: 2-step cycle,
    IMMEDIATE, INFINITE repeat)."""
    return _schedule_blink_cycle(controller, system, COLOR_AMBER,
                                 on_ms=500, off_ms=500, led_indices=None)
