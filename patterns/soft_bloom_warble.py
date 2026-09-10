"""soft_bloom_warble — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Calm aurora glow, green<->warm-white traveling warble.")


def schedule_soft_bloom_warble(controller, system):
    """Calm aurora glow: each LED slowly warbles Color1 (warm-white peak) <->
    Color0 (aurora-green trough) via selection-bit flips, with a per-LED phase
    offset so neighbours cross zero at different moments (a traveling wave).
    2-color palette + ONE global fade rate; per-LED phasing via 0x07/0x00 flips.
    One seamless loop (8000 ms)."""
    freq_hz = 0.5
    loop_seconds = 8.0
    phase_step_deg = 22.5
    color1_rgb = (255, 230, 200)
    color0_rgb = (40, 180, 60)
    fade_rate_idx = 4

    loop_ms = loop_seconds * 1000.0
    total_ms = loop_ms

    controller.add_event_at_time_ms(0, set_color0, system, *color0_rgb)
    controller.add_event_at_time_ms(0, set_color1, system, *color1_rgb)
    controller.add_event_at_time_ms(0, set_fade_rate, system, fade_rate_idx)
    controller.add_event_at_time_ms(0, select_all_leds, system, True, 0x00)

    phase_step_rad = math.radians(phase_step_deg)
    events_per_led = []
    for led_idx in range(TOTAL_LEDS):
        phi = led_idx * phase_step_rad
        led_events = []
        s0 = math.sin(phi)
        led_events.append((0.0, 0x07 if s0 > 0 else 0x00))
        max_k = int(2.0 * freq_hz * loop_seconds + 4)
        for kk in range(-2, max_k + 2):
            t = (kk * math.pi - phi) / (2 * math.pi * freq_hz)
            if 0.0 < t < loop_seconds:
                eps = 1e-6
                val = math.sin(2 * math.pi * freq_hz * (t + eps) + phi)
                led_events.append((t * 1000.0, 0x07 if val > 0 else 0x00))
        led_events.sort(key=lambda e: e[0])
        events_per_led.append(led_events)

    num_loops = int(math.ceil(total_ms / loop_ms))
    for loop_i in range(num_loops):
        loop_start_ms = loop_i * loop_ms
        for led_idx, led_events in enumerate(events_per_led):
            for (t_ms, bits) in led_events:
                if loop_i > 0 and t_ms == 0.0:
                    continue
                actual_ms = loop_start_ms + t_ms
                if actual_ms <= total_ms:
                    controller.add_event_at_time_ms(int(actual_ms), select_led, system, led_idx, True, bits)
    return int(total_ms)
