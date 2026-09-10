"""pendulum_swing_deterrence_red — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Red hotspot pendulum swing (deterrence).")


def schedule_pendulum_swing_deterrence_red(controller, system):
    """Deterrence: a red hotspot swings pendulum-style across the lower arc.
    Loop 10 s."""
    speed_hz, amp, width = 0.2, 5.0, 2.6

    def level(i, t_s):
        pos = (TOTAL_LEDS / 2.0) + math.sin(t_s * speed_hz * 2 * math.pi) * amp
        d = abs(i - pos)
        return math.cos((d / width) * math.pi / 2) if d < width else 0.0
    return _schedule_level_threshold(controller, system, level,
                                     (45, 8, 8), (255, 50, 20),
                                     fade_rate_idx=2, loop_seconds=10.0)
