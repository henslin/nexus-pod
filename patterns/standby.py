"""standby — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = 9400
RENDER_ONLY = False
DESCRIPTION = ("Standby: green CW comet x2 laps, solid 3 s, fade out.")


def schedule_standby(controller, system):
    """Standby: GREEN clockwise comet x2 laps -> solid green -> fade out. ~9.4 s.
    Identical motion and timing to arm_away — only the destination color differs.

    Green reads darker than Away's red at the same drive level. That is real —
    it is true on the device too — so it is NOT compensated: the per-hue green
    boost that used to live in `_compute_emission_strength` was removed
    2026-08-27 (see the note there). If the whole ring needs to be brighter for
    a render, raise EMISSION_STRENGTH / arlo_global_emission_boost, which lifts
    every hue equally and keeps preview == device."""
    return _schedule_spin_solid_fade(controller, system, STANDBY_GREEN)
