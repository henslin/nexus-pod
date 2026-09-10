"""firmware_update_dual_comet_varied_speed — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Blue/amber comets, varied speed.")


def schedule_firmware_update_dual_comet_varied_speed(controller, system):
    """Firmware Update (dual comet, varied speed): a BLUE comet spins CW from index 0 at
    3000ms/rotation while an AMBER comet spins CCW from index 15 at 3400ms/rotation (13%
    slower), for ~12 s. 2-color palette (Color0=blue, Color1=amber) set once; each head is
    a selected LED (blue 0x00, amber 0x07), a tail LED deselected — the 5-LED trail is the
    global fade engine (rate 2), not gradient colors."""
    rotation_ms_cw = 3000
    rotation_ms_ccw = 3400
    duration_seconds = 12.0
    fade_rate = 2
    trail_length = 5

    controller.add_event_at_time_ms(0, set_fade_rate, system, fade_rate)
    controller.add_event_at_time_ms(0, set_color0, system, *COLOR_BLUE)
    controller.add_event_at_time_ms(0, set_color1, system, *COLOR_AMBER)
    controller.add_event_at_time_ms(0, global_off, system)

    ms_per_led_cw = max(50, (rotation_ms_cw // TOTAL_LEDS) // 50 * 50)
    ms_per_led_ccw = max(50, (rotation_ms_ccw // TOTAL_LEDS) // 50 * 50)
    total_duration_ms = int(duration_seconds * 1000)

    start_cw = 0
    time_cw = 0
    step_cw = 0
    while time_cw < total_duration_ms:
        led_cw = (start_cw + step_cw) % TOTAL_LEDS
        controller.add_event_at_time_ms(time_cw, select_led, system, led_cw, True, 0x00)
        if step_cw >= trail_length:
            tail_cw = (start_cw + step_cw - trail_length) % TOTAL_LEDS
            controller.add_event_at_time_ms(time_cw, select_led, system, tail_cw, False, 0x00)
        step_cw += 1
        time_cw += ms_per_led_cw

    start_ccw = TOTAL_LEDS - 1
    time_ccw = 0
    step_ccw = 0
    while time_ccw < total_duration_ms:
        led_ccw = (start_ccw - step_ccw) % TOTAL_LEDS
        controller.add_event_at_time_ms(time_ccw, select_led, system, led_ccw, True, 0x07)
        if step_ccw >= trail_length:
            tail_ccw = (start_ccw - step_ccw + trail_length) % TOTAL_LEDS
            controller.add_event_at_time_ms(time_ccw, select_led, system, tail_ccw, False, 0x00)
        step_ccw += 1
        time_ccw += ms_per_led_ccw

    return total_duration_ms + 1000
