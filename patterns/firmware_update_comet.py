"""firmware_update_comet — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Alternating blue/amber comet.")


def schedule_firmware_update_comet(controller, system):
    """Firmware Update (comet): a comet head travels clockwise around the ring,
    alternating BLUE then AMBER each loop, for 6 cycles. 2-color palette
    (Color0=blue, Color1=amber) set once; the head is a single selected LED
    (0x00 blue / 0x07 amber) and the tail LED is deselected, the global fade rate
    (2) producing the fading trail."""
    rotation_ms = 1700
    num_cycles = 6
    fade_rate = 2
    trail_length = 1
    start_led = 0

    ms_per_led = max(50, (rotation_ms // TOTAL_LEDS) // 50 * 50)

    controller.add_event_at_time_ms(0, set_fade_rate, system, fade_rate)
    controller.add_event_at_time_ms(0, set_color0, system, *COLOR_BLUE)
    controller.add_event_at_time_ms(0, set_color1, system, *COLOR_AMBER)
    controller.add_event_at_time_ms(0, global_off, system)

    current_time_ms = 0
    for cycle in range(num_cycles):
        head_register = 0x00 if cycle % 2 == 0 else 0x07
        if cycle > 0:
            cleanup_time = current_time_ms - 1
            for i in range(trail_length):
                tail_led = (start_led + TOTAL_LEDS - trail_length + i) % TOTAL_LEDS
                controller.add_event_at_time_ms(cleanup_time, select_led, system, tail_led, False, 0x00)
        for step in range(TOTAL_LEDS):
            step_time_ms = current_time_ms + step * ms_per_led
            current_led = (start_led + step) % TOTAL_LEDS
            controller.add_event_at_time_ms(step_time_ms, select_led, system, current_led, True, head_register)
            if step >= trail_length:
                tail_led = (start_led + step - trail_length) % TOTAL_LEDS
                controller.add_event_at_time_ms(step_time_ms, select_led, system, tail_led, False, 0x00)
        current_time_ms += TOTAL_LEDS * ms_per_led

    controller.add_event_at_time_ms(current_time_ms + 500, global_off, system)
    return current_time_ms + 1000
