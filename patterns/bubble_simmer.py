"""bubble_simmer — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Random bubbles swell green->white->fade.")


def schedule_bubble_simmer(controller, system):
    """Localized organic motion: random bubbles spawn at random LEDs; each runs a
    4-flip lifecycle (green swell -> white core -> green fade -> off); the fade
    engine paints the ramps; overlaps take MAX (Color1 > Color0 > off). 2-color
    palette + ONE global fade rate + per-LED 0x07/0x00/off flips. Seeded Poisson,
    non-looping ~13 s bake (13000 ms)."""
    import random
    spawn_rate = 2.0
    max_simultaneous = 4
    size_range = (1, 3)
    swell_ms_range = (150, 350)
    hold_ms_range = (100, 600)
    fade_ms_range = (250, 600)
    color1_rgb = (255, 250, 240)
    color0_rgb = (30, 220, 110)
    fade_rate_idx = 3
    seed = 0

    if swell_ms_range[0] < 100:
        swell_ms_range = (max(100, swell_ms_range[0]), max(swell_ms_range[1], 100))
    if fade_ms_range[0] < 100:
        fade_ms_range = (max(100, fade_ms_range[0]), max(fade_ms_range[1], 100))
    if hold_ms_range[0] < 50:
        hold_ms_range = (max(50, hold_ms_range[0]), max(hold_ms_range[1], 50))

    total_ms = 13000.0
    c0_r, c0_g, c0_b = color0_rgb
    c1_r, c1_g, c1_b = color1_rgb
    controller.add_event_at_time_ms(0, set_color0, system, c0_r, c0_g, c0_b)
    controller.add_event_at_time_ms(0, set_color1, system, c1_r, c1_g, c1_b)
    controller.add_event_at_time_ms(0, set_fade_rate, system, fade_rate_idx)
    controller.add_event_at_time_ms(0, global_off, system)

    rng = random.Random(seed)
    bubbles = []
    spawn_until = total_ms - (swell_ms_range[1] + hold_ms_range[1] + fade_ms_range[1])
    spawn_until = max(spawn_until, 1000.0)
    spawn_interval_mean_ms = 1000.0 / max(0.01, spawn_rate)
    t = 0.0
    while t < spawn_until:
        alive = sum(1 for b in bubbles if b['spawn_ms'] <= t < b['end_ms'])
        if alive < max_simultaneous:
            b = {'spawn_ms': t, 'center': rng.randint(0, TOTAL_LEDS - 1),
                 'width': rng.randint(size_range[0], size_range[1]),
                 'swell_ms': rng.randint(swell_ms_range[0], swell_ms_range[1]),
                 'hold_ms': rng.randint(hold_ms_range[0], hold_ms_range[1]),
                 'fade_ms': rng.randint(fade_ms_range[0], fade_ms_range[1])}
            b['end_ms'] = b['spawn_ms'] + b['swell_ms'] + b['hold_ms'] + b['fade_ms']
            bubbles.append(b)
        t += rng.expovariate(1.0 / spawn_interval_mean_ms)

    for b in bubbles:
        half_low = b['width'] // 2
        half_high = b['width'] - half_low - 1
        b['footprint'] = set((b['center'] + off) % TOTAL_LEDS for off in range(-half_low, half_high + 1))

    tick_ms = 50
    last_states = [(False, 0x00)] * TOTAL_LEDS
    t_ms = 0
    while t_ms < total_ms:
        for led_idx in range(TOTAL_LEDS):
            target = None
            for b in bubbles:
                if t_ms < b['spawn_ms'] or t_ms >= b['end_ms']:
                    continue
                if led_idx not in b['footprint']:
                    continue
                local_t = t_ms - b['spawn_ms']
                sw, hl, fd = b['swell_ms'], b['hold_ms'], b['fade_ms']
                if local_t < sw / 2:
                    bubble_wants = 0x00
                elif local_t < sw + hl:
                    bubble_wants = 0x07
                elif local_t < sw + hl + fd / 2:
                    bubble_wants = 0x00
                else:
                    bubble_wants = None
                if bubble_wants == 0x07:
                    target = 0x07
                elif bubble_wants == 0x00 and target != 0x07:
                    target = 0x00
            if target == 0x07:
                new_state = (True, 0x07)
            elif target == 0x00:
                new_state = (True, 0x00)
            else:
                new_state = (False, 0x00)
            if new_state != last_states[led_idx]:
                controller.add_event_at_time_ms(t_ms, select_led, system, led_idx, new_state[0], new_state[1])
                last_states[led_idx] = new_state
        t_ms += tick_ms
    return int(total_ms)
