"""cellular_automaton_green — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Sierpinski-like binary-rule automaton, green.")


def schedule_cellular_automaton_green(controller, system):
    """Binary-rule cellular automaton: generation g lights LED i iff
    (i & g) == i — a Sierpinski-like unfolding. Loop 64 generations / ~10.67 s."""
    gen_speed, gen_period = 6, 64

    def level(i, t_s):
        g = int(t_s * gen_speed) % gen_period
        return 1.0 if (i & g) == i else 0.0
    return _schedule_level_threshold(controller, system, level,
                                     (5, 46, 22), (34, 197, 94),
                                     fade_rate_idx=2, loop_seconds=10.667)
