"""loading — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("HomePod-style white 'living breath' loading bubbles.")


def schedule_loading(controller, system):
    """"Living Breath" LOADING (HomePod-style, white-only): Color0 = base_white *
    resting_floor, Color1 = base_white * peak. A slow global breath rewrites both
    palettes together; random Poisson bubbles flip their footprint from Color0 to
    Color1 for a lifetime, then back. Never fully dark. 2-color palette + ONE
    global fade rate + per-LED 0x07/0x00 (floor never deselected) + global breath.
    Seeded, seam-wrapped. Loop 8000 ms."""
    import random
    resting_glow_floor = 0.25
    peak_brightness = 1.0
    base_white_rgb = (255, 250, 240)
    breath_hz = 0.25
    breath_depth = 0.20
    bubble_spawn_rate = 1.5
    max_simultaneous_bubbles = 4
    bubble_size_range = (1, 3)
    bubble_lifetime_ms_range = (400, 1000)
    fade_rate_idx = 3
    loop_seconds = 8.0
    seed = 0

    bw_r, bw_g, bw_b = base_white_rgb
    c0_r = max(0, min(255, int(round(bw_r * resting_glow_floor))))
    c0_g = max(0, min(255, int(round(bw_g * resting_glow_floor))))
    c0_b = max(0, min(255, int(round(bw_b * resting_glow_floor))))
    c1_r = max(0, min(255, int(round(bw_r * peak_brightness))))
    c1_g = max(0, min(255, int(round(bw_g * peak_brightness))))
    c1_b = max(0, min(255, int(round(bw_b * peak_brightness))))

    loop_ms = loop_seconds * 1000.0
    total_ms = loop_ms
    controller.add_event_at_time_ms(0, set_color0, system, c0_r, c0_g, c0_b)
    controller.add_event_at_time_ms(0, set_color1, system, c1_r, c1_g, c1_b)
    controller.add_event_at_time_ms(0, set_fade_rate, system, fade_rate_idx)
    controller.add_event_at_time_ms(0, select_all_leds, system, True, 0x00)

    rng = random.Random(seed)
    bubbles = []
    t = 0.0
    while t < loop_seconds:
        spawn_ms_now = t * 1000.0
        alive = sum(1 for b in bubbles if b['spawn_ms'] <= spawn_ms_now < b['end_ms'])
        if alive < max_simultaneous_bubbles:
            width = rng.randint(bubble_size_range[0], bubble_size_range[1])
            center = rng.randint(0, TOTAL_LEDS - 1)
            lifetime = rng.randint(bubble_lifetime_ms_range[0], bubble_lifetime_ms_range[1])
            hl = width // 2
            hh = width - hl - 1
            footprint = set((center + off) % TOTAL_LEDS for off in range(-hl, hh + 1))
            bubbles.append({'spawn_ms': spawn_ms_now, 'end_ms': spawn_ms_now + lifetime, 'footprint': footprint})
        t += rng.expovariate(bubble_spawn_rate)

    def bubble_active(b, t_ms):
        spawn_ms = b['spawn_ms']
        end_ms = b['end_ms']
        if spawn_ms <= t_ms < min(end_ms, loop_ms):
            return True
        if end_ms > loop_ms:
            wrap_dur_ms = end_ms - loop_ms
            if 0.0 <= t_ms < wrap_dur_ms:
                return True
        return False

    hue_tick_ms = 50
    last_states = [0x00] * TOTAL_LEDS
    hue_events_one_loop = []
    t_ms = 0
    while t_ms < loop_ms:
        for led_idx in range(TOTAL_LEDS):
            target = 0x00
            for b in bubbles:
                if led_idx not in b['footprint']:
                    continue
                if bubble_active(b, t_ms):
                    target = 0x07
                    break
            if target != last_states[led_idx]:
                hue_events_one_loop.append((t_ms, led_idx, target))
                last_states[led_idx] = target
        t_ms += hue_tick_ms

    def clamp_byte(v):
        return max(0, min(255, int(round(v))))

    breath_tick_ms = 200
    last_c0 = (c0_r, c0_g, c0_b)
    last_c1 = (c1_r, c1_g, c1_b)
    breath_events_one_loop = []
    t_ms = breath_tick_ms
    while t_ms < loop_ms:
        phase = 2.0 * math.pi * breath_hz * (t_ms / 1000.0)
        breath_factor = (1.0 - breath_depth) + breath_depth * (0.5 + 0.5 * math.sin(phase))
        new_c0 = (clamp_byte(c0_r * breath_factor), clamp_byte(c0_g * breath_factor), clamp_byte(c0_b * breath_factor))
        new_c1 = (clamp_byte(c1_r * breath_factor), clamp_byte(c1_g * breath_factor), clamp_byte(c1_b * breath_factor))
        if any(abs(new_c0[k] - last_c0[k]) >= 2 for k in range(3)):
            breath_events_one_loop.append((t_ms, "color0", new_c0))
            last_c0 = new_c0
        if any(abs(new_c1[k] - last_c1[k]) >= 2 for k in range(3)):
            breath_events_one_loop.append((t_ms, "color1", new_c1))
            last_c1 = new_c1
        t_ms += breath_tick_ms

    num_loops = int(math.ceil(total_ms / loop_ms))
    for loop_i in range(num_loops):
        base_ms = loop_i * loop_ms
        for (t_ms_local, led_idx, bits) in hue_events_one_loop:
            if loop_i > 0 and t_ms_local == 0:
                continue
            actual = base_ms + t_ms_local
            if actual <= total_ms:
                controller.add_event_at_time_ms(int(actual), select_led, system, led_idx, True, bits)
        for (t_ms_local, palette, rgb) in breath_events_one_loop:
            actual = base_ms + t_ms_local
            if actual <= total_ms:
                if palette == "color0":
                    controller.add_event_at_time_ms(int(actual), set_color0, system, *rgb)
                else:
                    controller.add_event_at_time_ms(int(actual), set_color1, system, *rgb)
    return int(total_ms)
