"""alarm_sos — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = 7560
RENDER_ONLY = False
DESCRIPTION = ("Triple-burst red alarm, 4 cycles.")


def schedule_alarm_sos(controller, system):
    """Triple-burst red alarm: 500 ms lead-off, then 4 cycles of {3x (flash on,
    flash off) + 800 ms gap}, then 500 ms trail-off. Byte-matches firmware
    alarm_sos (RING_ALL_SAME(RGB_ALARM_RED), 31MS fade, exact 110/170 ms flashes
    — the recorder honors exact durations, no tick)."""
    controller.add_event_at_time_ms(0, set_color0, system, 0, 0, 0)
    controller.add_event_at_time_ms(0, set_color1, system, *COLOR_ALARM_RED)
    controller.add_event_at_time_ms(0, set_fade_rate, system, 0)  # 31MS / IMMEDIATE
    controller.add_event_at_time_ms(0, select_all_leds, system, False, 0x00)
    flash_on, flash_off, gap = 110, 170, 800  # exact firmware timing
    t = 500  # lead-in silence
    for _cycle in range(4):
        for _burst in range(3):
            controller.add_event_at_time_ms(t, select_all_leds, system, True, 0x07)
            controller.add_event_at_time_ms(t + flash_on, select_all_leds, system, False, 0x00)
            t += flash_on + flash_off
        t += gap  # inter-cycle gap (stays off)
    return t + 500  # trailing silence
