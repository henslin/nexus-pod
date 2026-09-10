"""flocking_drift_connection_green — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Three drifting soft dots (connection), green.")


def schedule_flocking_drift_connection_green(controller, system):
    """Three soft dots drifting at slightly different speeds — flocking/
    connection feel. Non-integer speed ratios: loop seam not perfectly clean
    by design. Loop 12 s."""
    dot_count, speed_hz, spread, width = 3, 0.15, 0.35, 2.4

    def level(i, t_s):
        best = 0.0
        for k in range(dot_count):
            sp = speed_hz * (1.0 + k * spread)
            pos = ((t_s * sp) % 1.0) * TOTAL_LEDS
            best = max(best, max(0.0, 1.0 - _ring_distance(i, pos) / width))
        return best
    return _schedule_level_threshold(controller, system, level,
                                     (15, 61, 46), (102, 242, 194),
                                     fade_rate_idx=3, loop_seconds=12.0)
