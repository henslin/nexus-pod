"""strobe_pulsing_lattice_red — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Phase-spread pulsing lattice (alarm-adjacent); 1.8 Hz safety cap.")


def schedule_strobe_pulsing_lattice_red(controller, system):
    """Alarm-adjacent strobe: 4 anchor points pulse in a phase-spread lattice.
    SAFETY: flash rate is capped at 1.8 Hz on purpose, well under the 3-60 Hz
    photosensitive-seizure risk band — do NOT speed this up without a safety
    check. Loop ~3.33 s."""
    anchors, phase_spread, speed_hz = 4, 1.4, 1.8

    def level(i, t_s):
        step = TOTAL_LEDS / anchors
        idx = int(round(i / step)) % anchors
        d = _ring_distance(i, idx * step)
        local_pulse = 0.5 + 0.5 * math.sin(t_s * speed_hz * 2 * math.pi
                                           - idx * phase_spread)
        falloff = max(0.0, 1.0 - d / (step / 1.4))
        return local_pulse * falloff
    return _schedule_level_threshold(controller, system, level,
                                     (15, 3, 3), (255, 25, 15),
                                     fade_rate_idx=1, loop_seconds=3.333,
                                     threshold=0.55)
