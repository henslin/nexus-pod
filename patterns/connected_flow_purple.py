"""connected_flow_purple — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = 17400
RENDER_ONLY = False
DESCRIPTION = ("White breath -> purple trio bloom -> solid purple; state unassigned.")


def schedule_connected_flow_purple(controller, system):
    """Connected flow, purple with a slight pink lean — NOT yet assigned to a
    product state. Green is the enemy in this hue (it goes muddy grey), so G is
    pinned to ~16% of B and R sits at ~66% of B, deliberately on the purple side
    of magenta so it stays separable from the red armed state. 17.4 s.

    (The dim purple floor (25, 6, 38) this used to show in the gaps was retired
    when the sections were asked to be separated by blank ring.)"""
    return _schedule_connected_flow(controller, system, (168, 40, 255))
