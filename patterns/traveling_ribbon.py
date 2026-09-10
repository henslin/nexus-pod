"""traveling_ribbon — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Aurora curtain band sweeping back and forth + shimmer.")


def schedule_traveling_ribbon(controller, system):
    """Aurora curtain sweeping back and forth: a band selects Color1 (warm white)
    while the rest sit on Color0 (green); the band center sweeps sinusoidally, the
    fade engine trailing each LED the band leaves. A synchronized global palette
    shimmer + band-width breath layer on top. 2-color palette + ONE global fade
    rate; band via 0x07/0x00; shimmer = periodic palette rewrites. Loop 8000 ms."""
    sweep_period_s = 4.0
    reverse_sweep = True
    band_width = 6
    band_width_breath_amount = 1
    shimmer_hz = 0.25
    shimmer_depth = 0.20
    color1_rgb = (255, 250, 240)
    color0_rgb = (30, 220, 110)
    fade_rate_idx = 3
    loop_seconds = 8.0

    loop_ms = loop_seconds * 1000.0
    total_ms = loop_ms
    c0_r, c0_g, c0_b = color0_rgb
    c1_r, c1_g, c1_b = color1_rgb
    controller.add_event_at_time_ms(0, set_color0, system, c0_r, c0_g, c0_b)
    controller.add_event_at_time_ms(0, set_color1, system, c1_r, c1_g, c1_b)
    controller.add_event_at_time_ms(0, set_fade_rate, system, fade_rate_idx)
    controller.add_event_at_time_ms(0, select_all_leds, system, True, 0x00)

    def band_indices_at(t_s):
        if reverse_sweep:
            phase = (t_s % sweep_period_s) / sweep_period_s
            band_center = (TOTAL_LEDS - 1) * 0.5 * (1.0 - math.cos(2 * math.pi * phase))
        else:
            band_center = ((t_s % sweep_period_s) / sweep_period_s) * TOTAL_LEDS
        if band_width_breath_amount > 0 and shimmer_hz > 0:
            breath = band_width_breath_amount * math.sin(2 * math.pi * shimmer_hz * t_s)
            current_width = max(1, band_width + int(round(breath)))
        else:
            current_width = band_width
        center_idx = int(round(band_center))
        half_low = current_width // 2
        half_high = current_width - half_low - 1
        out = set()
        for offset in range(-half_low, half_high + 1):
            i = center_idx + offset
            if reverse_sweep:
                if 0 <= i < TOTAL_LEDS:
                    out.add(i)
            else:
                out.add(i % TOTAL_LEDS)
        return out

    band_events_one_loop = []
    tick_ms = 50
    last_state = set()
    t_ms = 0
    while t_ms < loop_ms:
        new_state = band_indices_at(t_ms / 1000.0)
        for i in sorted(new_state - last_state):
            band_events_one_loop.append((t_ms, i, 0x07))
        for i in sorted(last_state - new_state):
            band_events_one_loop.append((t_ms, i, 0x00))
        last_state = new_state
        t_ms += tick_ms

    shimmer_events_one_loop = []
    if shimmer_hz > 0 and shimmer_depth > 0:
        shimmer_period_ms = 1000.0 / shimmer_hz
        half = shimmer_period_ms / 2.0
        dim = 1.0 - shimmer_depth
        bright0 = (c0_r, c0_g, c0_b)
        dim0 = (int(c0_r * dim), int(c0_g * dim), int(c0_b * dim))
        bright1 = (c1_r, c1_g, c1_b)
        dim1 = (int(c1_r * dim), int(c1_g * dim), int(c1_b * dim))
        n = 1
        while True:
            t_ms_f = n * half
            if t_ms_f >= loop_ms:
                break
            if n % 2 == 1:
                shimmer_events_one_loop.append((int(round(t_ms_f)), "color0", dim0))
                shimmer_events_one_loop.append((int(round(t_ms_f)), "color1", dim1))
            else:
                shimmer_events_one_loop.append((int(round(t_ms_f)), "color0", bright0))
                shimmer_events_one_loop.append((int(round(t_ms_f)), "color1", bright1))
            n += 1

    num_loops = int(math.ceil(total_ms / loop_ms))
    for loop_i in range(num_loops):
        base_ms = loop_i * loop_ms
        for (t_ms, led_idx, bits) in band_events_one_loop:
            if loop_i > 0 and t_ms == 0:
                continue
            actual = base_ms + t_ms
            if actual <= total_ms:
                controller.add_event_at_time_ms(int(actual), select_led, system, led_idx, True, bits)
        for (t_ms, palette, rgb) in shimmer_events_one_loop:
            actual = base_ms + t_ms
            if actual <= total_ms:
                if palette == "color0":
                    controller.add_event_at_time_ms(int(actual), set_color0, system, *rgb)
                else:
                    controller.add_event_at_time_ms(int(actual), set_color1, system, *rgb)
    return int(total_ms)
