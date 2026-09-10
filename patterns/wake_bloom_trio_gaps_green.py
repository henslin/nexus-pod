"""wake_bloom_trio_gaps_green — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Three traveling dark gaps on a lit ring (constant brightness), green.")


def schedule_wake_bloom_trio_gaps_green(controller, system):
    """Wake bloom — trio gaps: the ring sits on the accent color and three
    equal 3-LED dark gaps, 120° apart, travel around it. Constant brightness —
    the level is a hard in-arc/out-of-arc test, never a continuous amplitude,
    so every accent LED matches every other accent LED at every instant.

    Dwell arithmetic (why fade_rate_idx=2, not the 5 the breathing "waiting"
    variant uses): speed = 2 rev * 16 LED / 8 s = 4 LED/s; a 3-LED gap dwells
    3/4 s = 750 ms >= 5*FADE_RATES[2] (625 ms), so each LED settles to full
    color before it flips again. FADE_RATES[3] (5*250 = 1250 ms) would smear.
    revolutions_per_loop must stay an INTEGER to keep the 8 s loop seamless."""
    n_arcs, gap_half_width, revolutions_per_loop, loop_seconds = 3, 1.5, 2, 8.0
    speed_leds_per_s = revolutions_per_loop * TOTAL_LEDS / loop_seconds

    def level(i, t_s):
        pos = (t_s * speed_leds_per_s) % TOTAL_LEDS
        return 0.0 if _in_any_arc(i, pos, gap_half_width, n_arcs) else 1.0
    return _schedule_level_threshold(controller, system, level,
                                     (2, 48, 14), (4, 255, 35),
                                     fade_rate_idx=2, loop_seconds=loop_seconds)
