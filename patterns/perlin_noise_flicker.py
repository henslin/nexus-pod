"""perlin_noise_flicker — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Organic Perlin-thresholded green/white twinkle.")


def schedule_perlin_noise_flicker(controller, system):
    """Organic, never-locked aurora: per LED per tick, sample 3D Perlin (time as a
    circle -> seamless loop) and threshold to Color1 (warm white) or Color0 (green).
    Each LED flips its own bit; the fade engine smooths flicks into cross-fades
    through mint. 2-color palette + ONE global fade rate + per-LED 0x07/0x00 flips.
    Pure-Python Perlin (headless). Loop 10000 ms."""
    noise_scale = 0.4
    scroll_speed = 0.25
    white_green_balance = 0.4
    color1_rgb = (255, 250, 240)
    color0_rgb = (30, 220, 110)
    fade_rate_idx = 3
    loop_seconds = 10.0
    seed = 0

    threshold = 1.0 - 2.0 * white_green_balance
    loop_ms = loop_seconds * 1000.0
    total_ms = loop_ms
    c0_r, c0_g, c0_b = color0_rgb
    c1_r, c1_g, c1_b = color1_rgb
    controller.add_event_at_time_ms(0, set_color0, system, c0_r, c0_g, c0_b)
    controller.add_event_at_time_ms(0, set_color1, system, c1_r, c1_g, c1_b)
    controller.add_event_at_time_ms(0, set_fade_rate, system, fade_rate_idx)
    controller.add_event_at_time_ms(0, select_all_leds, system, True, 0x00)

    scroll_radius = scroll_speed * loop_seconds
    seed_offset = float(seed) * 1000.0

    def sample_noise(led_idx, t_s):
        x = led_idx * noise_scale + seed_offset
        t_phase = 2 * math.pi * (t_s / loop_seconds)
        y = scroll_radius * math.cos(t_phase)
        z = scroll_radius * math.sin(t_phase)
        return _perlin_noise_3d(x, y, z)

    tick_ms = 50
    events_one_loop = []
    last_states = [None] * TOTAL_LEDS
    t_ms = 0
    while t_ms < loop_ms:
        t_s = t_ms / 1000.0
        for i in range(TOTAL_LEDS):
            n = sample_noise(i, t_s)
            new_bits = 0x07 if n > threshold else 0x00
            if new_bits != last_states[i]:
                events_one_loop.append((t_ms, i, new_bits))
                last_states[i] = new_bits
        t_ms += tick_ms

    num_loops = int(math.ceil(total_ms / loop_ms))
    for loop_i in range(num_loops):
        base_ms = loop_i * loop_ms
        for (t_ms, led_idx, bits) in events_one_loop:
            if loop_i > 0 and t_ms == 0:
                continue
            actual = base_ms + t_ms
            if actual <= total_ms:
                controller.add_event_at_time_ms(int(actual), select_led, system, led_idx, True, bits)
    return int(total_ms)
