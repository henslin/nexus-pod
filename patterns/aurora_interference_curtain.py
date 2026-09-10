"""aurora_interference_curtain — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Two counter-propagating waves; drifting antinodes.")


def schedule_aurora_interference_curtain(controller, system):
    """Two counter-propagating sine waves of slightly different frequencies sum
    into a standing wave whose antinodes drift at the beat frequency; per LED per
    tick the interference value thresholds to Color1 (white antinode) or Color0
    (green node); the fade engine paints the transitions. 2-color palette + ONE
    global fade rate + per-LED 0x07/0x00 flips. Loop 10000 ms."""
    wave_a_hz = 0.3
    wave_b_hz = 0.4
    wave_a_cycles = 2
    wave_b_cycles = 2
    amplitude = 1.0
    white_green_balance = 0.5
    color1_rgb = (255, 250, 240)
    color0_rgb = (30, 220, 110)
    fade_rate_idx = 3
    loop_seconds = 10.0

    loop_ms = loop_seconds * 1000.0
    total_ms = loop_ms
    threshold = (2.0 * amplitude) * (1.0 - 2.0 * white_green_balance)
    c0_r, c0_g, c0_b = color0_rgb
    c1_r, c1_g, c1_b = color1_rgb
    controller.add_event_at_time_ms(0, set_color0, system, c0_r, c0_g, c0_b)
    controller.add_event_at_time_ms(0, set_color1, system, c1_r, c1_g, c1_b)
    controller.add_event_at_time_ms(0, set_fade_rate, system, fade_rate_idx)
    controller.add_event_at_time_ms(0, select_all_leds, system, True, 0x00)

    omega_a = 2.0 * math.pi * wave_a_hz
    omega_b = 2.0 * math.pi * wave_b_hz
    spatial_a = lambda i: wave_a_cycles * 2.0 * math.pi * i / TOTAL_LEDS
    spatial_b = lambda i: wave_b_cycles * 2.0 * math.pi * i / TOTAL_LEDS

    tick_ms = 50
    events_one_loop = []
    last_states = [None] * TOTAL_LEDS
    t_ms = 0
    while t_ms < loop_ms:
        t_s = t_ms / 1000.0
        for i in range(TOTAL_LEDS):
            wa = amplitude * math.sin(omega_a * t_s + spatial_a(i))
            wb = amplitude * math.sin(omega_b * t_s - spatial_b(i))
            interference = wa + wb
            new_bits = 0x07 if interference > threshold else 0x00
            if new_bits != last_states[i]:
                events_one_loop.append((t_ms, i, new_bits))
                last_states[i] = new_bits
        t_ms += tick_ms

    num_loops = int(math.ceil(total_ms / loop_ms))
    for loop_i in range(num_loops):
        base_ms = loop_i * loop_ms
        for (t_ms_local, led_idx, bits) in events_one_loop:
            if loop_i > 0 and t_ms_local == 0:
                continue
            actual = base_ms + t_ms_local
            if actual <= total_ms:
                controller.add_event_at_time_ms(int(actual), select_led, system, led_idx, True, bits)
    return int(total_ms)
