"""speaking_response_waveform_blue — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Word-burst waveform bars (speaking), blue.")


def schedule_speaking_response_waveform_blue(controller, system):
    """Speaking: word-burst envelopes over a 3-bar rotating waveform; the lit
    floor keeps the ring visibly awake between words. Loop 8.8 s."""
    word_period, bars, speed_hz = 1.1, 3, 0.5

    def level(i, t_s):
        word_idx = int(t_s / word_period)
        wfrac = (t_s % word_period) / word_period
        env = math.sin(min(1.0, wfrac) * math.pi)
        bar = 0.5 + 0.5 * math.sin(2 * math.pi * (i / TOTAL_LEDS) * bars
                                   + t_s * speed_hz * 2 * math.pi
                                   + _hash01(word_idx, i) * 2)
        return max(0.0, env) * bar
    return _schedule_level_threshold(controller, system, level,
                                     (26, 48, 86), (60, 150, 255),
                                     fade_rate_idx=3, loop_seconds=8.8,
                                     threshold=0.42)
