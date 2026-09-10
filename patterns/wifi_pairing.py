"""wifi_pairing — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = 5492
RENDER_ONLY = False
DESCRIPTION = ("Dual green comet spin.")


def schedule_wifi_pairing(controller, system):
    """Dual green comet (CW + CCW), one rotation, FAST, 312 ms/frame, plus a
    trailing MEDIUM RING_ALL_OFF. Byte-matches firmware wifi_pairing
    (16x SPIN_FRAME(cw, ccw, RGB_GREEN) + off)."""
    end = _schedule_spin_firmware(controller, system, COLOR_GREEN)
    controller.add_event_at_time_ms(end, set_fade_rate, system, 4)  # MEDIUM, matches firmware tail
    controller.add_event_at_time_ms(end, select_all_leds, system, False, 0x00)
    return end + 500
