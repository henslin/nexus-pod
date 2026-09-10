"""firmware_update_failed — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = 3000
RENDER_ONLY = False
DESCRIPTION = ("Solid red 3 s (firmware update failed).")


def schedule_firmware_update_failed(controller, system):
    """Solid red 3 s; renderer auto-offs (firmware: 1 step, MEDIUM)."""
    return _schedule_solid_firmware(controller, system, COLOR_RED, off_ms=0)
