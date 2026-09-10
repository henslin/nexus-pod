"""utterance_loudness_envelope_blue — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Loudness envelope with sub-pulses (speaking), blue.")


def schedule_utterance_loudness_envelope_blue(controller, system):
    """Speaking: a loudness envelope with sub-pulses travels around the ring
    with a per-LED lag. Loop 10.2 s (3 utterances)."""
    utt_period, sub_pulses, lag_amt = 3.4, 4, 0.5

    def level(i, t_s):
        ph = (t_s % utt_period) / utt_period
        ph_lag = max(0.0, min(1.0, ph - (i / TOTAL_LEDS) * lag_amt))
        return ((max(0.0, math.sin(ph_lag * math.pi)) ** 0.6)
                * (0.6 + 0.4 * math.sin(ph_lag * math.pi * sub_pulses)))
    return _schedule_level_threshold(controller, system, level,
                                     (14, 16, 64), (80, 160, 255),
                                     fade_rate_idx=4, loop_seconds=10.2,
                                     threshold=0.35)
