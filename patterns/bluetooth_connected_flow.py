"""bluetooth_connected_flow — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = 17400
RENDER_ONLY = False
DESCRIPTION = ("White breath -> sapphire trio bloom -> solid sapphire (connected).")


def schedule_bluetooth_connected_flow(controller, system):
    """Bluetooth: white breathing → sapphire wake bloom → solid sapphire (held).
    The accent keeps R and G low on purpose — the saturated blue the design
    review asked for. 17.4 s.

    (The dim sapphire floor (1, 5, 40) this used to show in the gaps was retired
    when the sections were asked to be separated by blank ring.)"""
    return _schedule_connected_flow(controller, system, (40, 60, 255))
