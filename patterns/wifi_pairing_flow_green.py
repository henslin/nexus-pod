"""wifi_pairing_flow_green — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = 17400
RENDER_ONLY = False
DESCRIPTION = ("White breath -> green trio bloom -> solid green (paired).")


def schedule_wifi_pairing_flow_green(controller, system):
    """Wi-Fi pairing: white breathing → green wake bloom → solid green (paired).
    Same motion as the Bluetooth flow, emerald palette — blue held at ~34% of
    green (lower slides to lime, higher to mint) and red near zero. 17.4 s.

    (The dim green floor (1, 36, 12) this used to show in the gaps was retired
    when the sections were asked to be separated by blank ring.)"""
    return _schedule_connected_flow(controller, system, (16, 244, 84))
