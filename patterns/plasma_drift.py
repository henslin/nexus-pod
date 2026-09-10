"""plasma_drift — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Calm ambient drifting green/white zones + palette breath.")


def schedule_plasma_drift(controller, system):
    """Calm ambient: soft green/white zones drift and morph, no LED going dark.
    Layer A = per-LED 3D Perlin thresholded to Color0/Color1 (drifting fronts).
    Layer B = a global 3D Perlin modulating BOTH palette RGBs via periodic
    rewrites (a synchronized breath). Time-as-circle for a seamless loop. 2-color
    palette + ONE global fade rate + per-LED 0x07/0x00 (never deselected) + global
    palette breath. Pure-Python Perlin (headless). Loop 14000 ms."""
    drift_speed = 0.05
    zone_scale = 5.0
    brightness_min = 0.70
    white_green_balance = 0.5
    color1_rgb = (255, 250, 240)
    color0_rgb = (30, 220, 110)
    fade_rate_idx = 3
    loop_seconds = 14.0
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

    seed_offset_a = float(seed) * 1000.0
    seed_offset_b = float(seed) * 1000.0 + 13.37
    scroll_radius_a = drift_speed * loop_seconds
    scroll_radius_b = 2.0 * drift_speed * loop_seconds

    def sample_hue(led_idx, t_s):
        x = led_idx / zone_scale + seed_offset_a
        phase = 2.0 * math.pi * (t_s / loop_seconds)
        y = scroll_radius_a * math.cos(phase)
        z = scroll_radius_a * math.sin(phase)
        return _perlin_noise_3d(x, y, z)

    def sample_brightness(t_s):
        phase = 2.0 * math.pi * (t_s / loop_seconds)
        y = scroll_radius_b * math.cos(phase)
        z = scroll_radius_b * math.sin(phase)
        return _perlin_noise_3d(seed_offset_b, y, z)

    def clamp_byte(v):
        return max(0, min(255, int(round(v))))

    hue_tick_ms = 50
    last_states = [None] * TOTAL_LEDS
    hue_events_one_loop = []
    t_ms = 0
    while t_ms < loop_ms:
        t_s = t_ms / 1000.0
        for i in range(TOTAL_LEDS):
            n = sample_hue(i, t_s)
            new_bits = 0x07 if n > threshold else 0x00
            if new_bits != last_states[i]:
                hue_events_one_loop.append((t_ms, i, new_bits))
                last_states[i] = new_bits
        t_ms += hue_tick_ms

    bright_tick_ms = 200
    bright_events_one_loop = []
    last_c0 = (c0_r, c0_g, c0_b)
    last_c1 = (c1_r, c1_g, c1_b)
    t_ms = bright_tick_ms
    while t_ms < loop_ms:
        n = sample_brightness(t_ms / 1000.0)
        dim = brightness_min + (1.0 - brightness_min) * (n * 0.5 + 0.5)
        dim = max(0.1, min(1.0, dim))
        new_c0 = (clamp_byte(c0_r * dim), clamp_byte(c0_g * dim), clamp_byte(c0_b * dim))
        new_c1 = (clamp_byte(c1_r * dim), clamp_byte(c1_g * dim), clamp_byte(c1_b * dim))
        if any(abs(new_c0[k] - last_c0[k]) >= 2 for k in range(3)):
            bright_events_one_loop.append((t_ms, "color0", new_c0))
            last_c0 = new_c0
        if any(abs(new_c1[k] - last_c1[k]) >= 2 for k in range(3)):
            bright_events_one_loop.append((t_ms, "color1", new_c1))
            last_c1 = new_c1
        t_ms += bright_tick_ms

    num_loops = int(math.ceil(total_ms / loop_ms))
    for loop_i in range(num_loops):
        base_ms = loop_i * loop_ms
        for (t_ms_local, led_idx, bits) in hue_events_one_loop:
            if loop_i > 0 and t_ms_local == 0:
                continue
            actual = base_ms + t_ms_local
            if actual <= total_ms:
                controller.add_event_at_time_ms(int(actual), select_led, system, led_idx, True, bits)
        for (t_ms_local, palette, rgb) in bright_events_one_loop:
            actual = base_ms + t_ms_local
            if actual <= total_ms:
                if palette == "color0":
                    controller.add_event_at_time_ms(int(actual), set_color0, system, *rgb)
                else:
                    controller.add_event_at_time_ms(int(actual), set_color1, system, *rgb)
    return int(total_ms)
