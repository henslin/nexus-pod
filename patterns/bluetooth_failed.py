"""bluetooth_failed — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = 10500
RENDER_ONLY = False
DESCRIPTION = ("Amber/red alternating 10 s.")


def schedule_bluetooth_failed(controller, system):
    """Amber/red alternating (firmware: 2-step cycle, IMMEDIATE 500/500,
    renderer repeats over ~10.5 s)."""
    return _schedule_alternating_firmware(controller, system,
                                          [COLOR_AMBER, COLOR_RED], interval_ms=500)
