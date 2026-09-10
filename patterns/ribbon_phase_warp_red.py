"""ribbon_phase_warp_red — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Phase-warped organic red ribbon sweep.")


def schedule_ribbon_phase_warp_red(controller, system):
    """Red ribbon whose phase is warped by a second slow sine — an organic,
    non-repeating-feeling sweep. Non-integer speed ratios: loop seam not
    perfectly clean by design. Loop 10 s."""
    speed_hz, warp_amt, warp_freq, warp_speed = 0.28, 1.6, 2.5, 1.1

    def level(i, t_s):
        base = (i / TOTAL_LEDS) - t_s * speed_hz
        warped = math.sin(base * 2 * math.pi
                          + warp_amt * math.sin(base * 2 * math.pi * warp_freq
                                                + t_s * warp_speed))
        return 0.5 + 0.5 * warped
    return _schedule_level_threshold(controller, system, level,
                                     (50, 10, 10), (255, 70, 40),
                                     fade_rate_idx=3, loop_seconds=10.0)
