"""mic_level_jitter_listening_blue — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Synthesized mic-level jitter (listening), blue.")


def schedule_mic_level_jitter_listening_blue(controller, system):
    """Listening: a synthesized 3-harmonic 'mic level' drives the whole ring,
    with a per-LED hashed offset so LEDs light in a scattered order. Loop 8 s."""
    speed_hz = 0.294

    def level(i, t_s):
        level_acc, wsum = 0.0, 0.0
        for k in range(3):
            w = 1.0 / (k + 1)
            level_acc += w * (0.5 + 0.5 * math.sin(t_s * speed_hz * (k + 1) * 1.7
                                                   * 2 * math.pi
                                                   + _hash01(k, 3) * 10))
            wsum += w
        level_acc /= wsum
        off = _hash01(i, 1) * 0.25
        return max(0.0, level_acc - off * (1.0 - level_acc))
    return _schedule_level_threshold(controller, system, level,
                                     (10, 34, 72), (40, 130, 255),
                                     fade_rate_idx=3, loop_seconds=8.0)
