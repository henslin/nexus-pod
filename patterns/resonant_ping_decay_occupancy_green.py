"""resonant_ping_decay_occupancy_green — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Damped-oscillator ping + decay (occupancy), green.")


def schedule_resonant_ping_decay_occupancy_green(controller, system):
    """Occupancy: a damped-oscillator 'ping' rings the whole ring and decays,
    repeating every 2.6 s. Loop 10.4 s (4 pings)."""
    period, damping, freq = 2.6, 1.3, 1.8

    def level(i, t_s):
        age = ((t_s % period) / period) * period
        ping = math.exp(-age * damping) * math.cos(age * freq * 2 * math.pi)
        return max(0.0, 0.5 + 0.5 * ping)
    return _schedule_level_threshold(controller, system, level,
                                     (8, 51, 31), (22, 201, 138),
                                     fade_rate_idx=4, loop_seconds=10.4)
