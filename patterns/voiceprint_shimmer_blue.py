"""voiceprint_shimmer_blue — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Hashed voiceprint + shimmer (listening idle), blue.")


def schedule_voiceprint_shimmer_blue(controller, system):
    """Listening idle: a fixed hashed 'voiceprint' per LED with a gentle
    shimmer riding on it. Loop 10 s."""
    shimmer_speed = 1.6

    def level(i, t_s):
        base_pattern = _hash01(i, 41)
        shimmer = 0.15 * math.sin(t_s * shimmer_speed * 2 * math.pi + i * 0.7)
        return max(0.0, min(1.0, base_pattern * 0.8 + shimmer))
    return _schedule_level_threshold(controller, system, level,
                                     (18, 24, 58), (140, 160, 255),
                                     fade_rate_idx=4, loop_seconds=10.0)
