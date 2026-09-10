"""quantum_tunneling_speaking_blue — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Tunneling bright spot with arrival flash (speaking), blue.")


def schedule_quantum_tunneling_speaking_blue(controller, system):
    """Speaking: a bright spot 'tunnels' — vanishes and reappears at hashed
    positions with a brief arrival flash + wiggle. Jump positions come from a
    continuous hash, so a small pop at the loop seam is expected. Loop 8 s."""
    jump_rate, wiggle_speed, wiggle_amt, width = 0.9, 2.5, 0.6, 1.6

    def level(i, t_s):
        seed = int(t_s * jump_rate)
        frac = (t_s * jump_rate) % 1.0
        pos = (_hash01(seed, 1) * TOTAL_LEDS
               + math.sin(t_s * wiggle_speed * 2 * math.pi + seed) * wiggle_amt) \
            % TOTAL_LEDS
        lvl = 1.0 if _ring_distance(i, pos) < width else 0.0
        if frac < 0.08:
            lvl = min(1.0, lvl + 0.4)
        return lvl
    return _schedule_level_threshold(controller, system, level,
                                     (14, 16, 64), (58, 110, 240),
                                     fade_rate_idx=3, loop_seconds=8.0)
