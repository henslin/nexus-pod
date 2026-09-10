"""tidal_modulation_loading_green — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Slow tide amplitude-modulating a fast ripple (loading).")


def schedule_tidal_modulation_loading_green(controller, system):
    """Loading: a slow 1-cycle tide amplitude-modulating a fast 5-cycle ripple.
    Loop 20 s."""
    slow_speed, fast_speed, slow_cycles, fast_cycles = 0.12, 0.55, 1, 5

    def level(i, t_s):
        slow = 0.5 + 0.5 * math.sin(2 * math.pi * (i / TOTAL_LEDS) * slow_cycles
                                    - t_s * slow_speed * 2 * math.pi)
        fast = 0.5 + 0.5 * math.sin(2 * math.pi * (i / TOTAL_LEDS) * fast_cycles
                                    - t_s * fast_speed * 2 * math.pi)
        return slow * (0.4 + 0.6 * fast)
    return _schedule_level_threshold(controller, system, level,
                                     (15, 61, 46), (102, 242, 194),
                                     fade_rate_idx=5, loop_seconds=20.0)
