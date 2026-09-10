"""
pattern_common.py — shared vocabulary + engines for the per-pattern modules
===========================================================================
Everything the patterns/<name>.py modules share: the firmware color palette,
LED position helpers, the generic scheduling engines (blink/cascade/spin/
solid/level-threshold/comet/breath/connected-flow/ripple), the Perlin noise
core, and the ripple motion-math loader.

Imports ONLY from led_ring_core (never from led_ring_patterns or patterns/*
— that would be circular). A pattern module starts with:

    from pattern_common import *          # public vocabulary
    from pattern_common import (<the underscore engines it needs>)

Rules unchanged from CLAUDE.md: engines speak only the 2-color Frozen API,
colors mirror the firmware RGB_* macros, and nothing here touches Blender.
"""

from typing import Callable, Dict, List, Optional, Tuple
import colorsys
import math

from led_ring_core import (
    TOTAL_LEDS,
    set_color0, set_color1, set_fade_rate,
    select_led, select_all_leds, global_off,
    set_driver_color0, set_driver_color1,   # render_only patterns ONLY
    schedule_steps,
)


COLOR_WHITE = (255, 255, 255)        # RGB_WHITE


COLOR_BLUE = (0, 0, 255)             # RGB_BLUE


COLOR_GREEN = (0, 255, 0)            # RGB_GREEN


COLOR_RED = (255, 0, 0)             # RGB_RED


COLOR_AMBER = (255, 126, 0)          # RGB_AMBER  (firmware value; was 255,76,0)


COLOR_ALARM_RED = (220, 0, 0)        # RGB_ALARM_RED


COLOR_LIGHT_GREEN = (40, 215, 10)    # RGB_LIGHT_GREEN


COLOR_GREEN_WHITE = (120, 255, 60)   # RGB_GREEN_WHITE


COLOR_BLACK = (0, 0, 0)

# ============================================================================
# RING GEOMETRY HELPERS
# ============================================================================


TOP_LEDS = [0, TOTAL_LEDS - 1]


BOTTOM_LEDS = [TOTAL_LEDS // 2 - 1, TOTAL_LEDS // 2]


RIGHT_HALF = list(range(0, TOTAL_LEDS // 2))


LEFT_HALF = list(range(TOTAL_LEDS // 2, TOTAL_LEDS))


SYMMETRIC_PAIRS = [(i, TOTAL_LEDS - 1 - i) for i in range(TOTAL_LEDS // 2)]


def led_clockwise(index):
    return (index + 1) % TOTAL_LEDS


def led_counter_clockwise(index):
    return (index - 1) % TOTAL_LEDS


def led_opposite(index):
    return (index + TOTAL_LEDS // 2) % TOTAL_LEDS


def led_mirror(index):
    return (TOTAL_LEDS - 1 - index) % TOTAL_LEDS


# ============================================================================
# SCHEDULE HELPERS  (shared building blocks; identical semantics to originals)
# ============================================================================


def schedule_solid_color(controller, system, color, start_ms, duration_ms,
                         fade_off=True, fade_in_rate=5, fade_out_rate=None):
    """Solid color with optional separate fade-in/out rates. Default fade-out is
    ~2 steps faster than fade-in to counter the chip's slow decay."""
    if fade_out_rate is None:
        fade_out_rate = max(0, fade_in_rate - 2)
    r, g, b = color
    controller.add_event_at_time_ms(start_ms, set_color0, system, 0, 0, 0)
    controller.add_event_at_time_ms(start_ms, set_color1, system, r, g, b)
    controller.add_event_at_time_ms(start_ms, set_fade_rate, system, fade_in_rate)
    controller.add_event_at_time_ms(start_ms, select_all_leds, system, True, 0x07)
    if fade_off:
        off_time = start_ms + duration_ms
        controller.add_event_at_time_ms(off_time, set_fade_rate, system, fade_out_rate)
        controller.add_event_at_time_ms(off_time, select_all_leds, system, True, 0x00)


def schedule_blink_pattern(controller, system, color, on_ms, off_ms, duration_ms,
                           led_indices=None, start_ms=0, fade_rate=0):
    """Blink some/all LEDs between Color1 (on) and Color0=black (off)."""
    r, g, b = color
    cycle_ms = on_ms + off_ms
    num_cycles = int(duration_ms / cycle_ms)
    controller.add_event_at_time_ms(start_ms, set_color0, system, 0, 0, 0)
    controller.add_event_at_time_ms(start_ms, set_color1, system, r, g, b)
    controller.add_event_at_time_ms(start_ms, set_fade_rate, system, fade_rate)
    for cycle in range(num_cycles):
        cycle_start = start_ms + cycle * cycle_ms
        if led_indices is None:
            controller.add_event_at_time_ms(cycle_start, select_all_leds, system, True, 0x07)
        else:
            for idx in led_indices:
                controller.add_event_at_time_ms(cycle_start, select_led, system, idx, True, 0x07)
        off_time = cycle_start + on_ms
        if led_indices is None:
            controller.add_event_at_time_ms(off_time, select_all_leds, system, True, 0x00)
        else:
            for idx in led_indices:
                controller.add_event_at_time_ms(off_time, select_led, system, idx, False, 0x00)


def schedule_dual_spin_pattern(controller, system, color, rotation_ms=5000,
                               num_rotations=1, start_ms=0, fade_rate=2,
                               trail_length=4, head_brightness=1.0, trail_brightness=0.3):
    """Two comets (CW + CCW): Color1=bright head, Color0=dim trail. Hardware
    fade engines render the tail decay."""
    r, g, b = color
    dim_r, dim_g, dim_b = int(r * trail_brightness), int(g * trail_brightness), int(b * trail_brightness)
    br_r, br_g, br_b = int(r * head_brightness), int(g * head_brightness), int(b * head_brightness)
    controller.add_event_at_time_ms(start_ms, set_fade_rate, system, fade_rate)
    controller.add_event_at_time_ms(start_ms, set_color0, system, dim_r, dim_g, dim_b)
    controller.add_event_at_time_ms(start_ms, set_color1, system, br_r, br_g, br_b)
    controller.add_event_at_time_ms(start_ms, global_off, system)

    ms_per_led = max(50, (rotation_ms // TOTAL_LEDS) // 50 * 50)
    start_cw, start_ccw = 0, TOTAL_LEDS - 1
    total_steps = num_rotations * TOTAL_LEDS
    for step in range(total_steps):
        time_ms = start_ms + step * ms_per_led
        head_cw = (start_cw + step) % TOTAL_LEDS
        head_ccw = (start_ccw - step) % TOTAL_LEDS
        controller.add_event_at_time_ms(time_ms, select_led, system, head_cw, True, 0x07)
        controller.add_event_at_time_ms(time_ms, select_led, system, head_ccw, True, 0x07)
        if step >= 1:
            prev_cw = (start_cw + step - 1) % TOTAL_LEDS
            prev_ccw = (start_ccw - step + 1) % TOTAL_LEDS
            controller.add_event_at_time_ms(time_ms, select_led, system, prev_cw, True, 0x00)
            controller.add_event_at_time_ms(time_ms, select_led, system, prev_ccw, True, 0x00)
        if step >= trail_length:
            tail_cw = (start_cw + step - trail_length) % TOTAL_LEDS
            tail_ccw = (start_ccw - step + trail_length) % TOTAL_LEDS
            controller.add_event_at_time_ms(time_ms, select_led, system, tail_cw, False, 0x00)
            controller.add_event_at_time_ms(time_ms, select_led, system, tail_ccw, False, 0x00)
    final_time_ms = start_ms + total_steps * ms_per_led
    for i in range(trail_length):
        off_time = final_time_ms + i * ms_per_led
        tail_cw = (start_cw + total_steps - trail_length + i) % TOTAL_LEDS
        tail_ccw = (start_ccw - total_steps + trail_length - i) % TOTAL_LEDS
        controller.add_event_at_time_ms(off_time, select_led, system, tail_cw, False, 0x00)
        controller.add_event_at_time_ms(off_time, select_led, system, tail_ccw, False, 0x00)
    return final_time_ms + trail_length * ms_per_led + 500


def schedule_cascade_pattern(controller, system, color, num_leds, ms_per_led,
                             start_ms=0, blink_last=True, blink_duration_ms=5000,
                             blink_on_ms=300, blink_off_ms=300, fade_rate=3,
                             blink_fade_rate=0):
    """LEDs light up one by one clockwise; optionally blink the last one."""
    r, g, b = color
    controller.add_event_at_time_ms(start_ms, set_color0, system, 0, 0, 0)
    controller.add_event_at_time_ms(start_ms, set_color1, system, r, g, b)
    controller.add_event_at_time_ms(start_ms, set_fade_rate, system, fade_rate)
    controller.add_event_at_time_ms(start_ms, global_off, system)
    cascade_end_ms = start_ms
    for i in range(num_leds):
        led_on_time = start_ms + i * ms_per_led
        controller.add_event_at_time_ms(led_on_time, select_led, system, i, True, 0x07)
        cascade_end_ms = led_on_time
    if blink_last and num_leds < TOTAL_LEDS:
        last_led_idx = num_leds - 1
        blink_start_ms = cascade_end_ms + ms_per_led
        controller.add_event_at_time_ms(blink_start_ms, set_fade_rate, system, blink_fade_rate)
        cycle_ms = blink_on_ms + blink_off_ms
        num_blink_cycles = int(blink_duration_ms / cycle_ms)
        for cycle in range(num_blink_cycles):
            cycle_start = blink_start_ms + cycle * cycle_ms
            controller.add_event_at_time_ms(cycle_start, select_led, system, last_led_idx, False, 0x00)
            controller.add_event_at_time_ms(cycle_start + blink_off_ms, select_led, system, last_led_idx, True, 0x07)
        return blink_start_ms + blink_duration_ms
    return cascade_end_ms + blink_duration_ms


def schedule_alternating_colors(controller, system, color1, color2, interval_ms,
                                duration_ms, start_ms=0, fade_rate=0):
    """All LEDs alternate between two colors by rewriting Color1 in lockstep."""
    r1, g1, b1 = color1
    r2, g2, b2 = color2
    num_switches = int(duration_ms / interval_ms)
    for i in range(num_switches):
        switch_time = start_ms + i * interval_ms
        if i % 2 == 0:
            controller.add_event_at_time_ms(switch_time, set_color1, system, r1, g1, b1)
        else:
            controller.add_event_at_time_ms(switch_time, set_color1, system, r2, g2, b2)
        controller.add_event_at_time_ms(switch_time, set_fade_rate, system, fade_rate)
        controller.add_event_at_time_ms(switch_time, select_all_leds, system, True, 0x07)
    end_ms = start_ms + duration_ms
    controller.add_event_at_time_ms(end_ms, select_all_leds, system, True, 0x00)
    return end_ms


# ============================================================================
# PATTERN SCHEDULERS
# ============================================================================
# Each `schedule_<name>(controller, system)` stages the pattern's commands and
# returns its total duration in ms. They are registered in PATTERNS below with
# metadata. Preview/export drivers call these; the scheduler never touches
# Blender or the exporter directly.


def _schedule_solid_firmware(controller, system, color, hold_ms=3000,
                             off_ms=1000, fade_idx=4):
    """Firmware-exact solid: one MEDIUM fade-in to `color` held `hold_ms`, then
    (if off_ms) one MEDIUM fade to off held `off_ms`. Records to the firmware's
    2-step `RING_ALL_SAME(RGB_x)` + `RING_ALL_OFF` form (or 1 step if off_ms=0).
    fade_idx 4 == MEDIUM. Matches power_on_success / *_success / *_critical /
    firmware_update_success|failed in agw_ringled_patterns_harpy.c."""
    r, g, b = color
    controller.add_event_at_time_ms(0, set_color0, system, 0, 0, 0)
    controller.add_event_at_time_ms(0, set_color1, system, r, g, b)
    controller.add_event_at_time_ms(0, set_fade_rate, system, fade_idx)
    controller.add_event_at_time_ms(0, select_all_leds, system, True, 0x07)
    if off_ms:
        controller.add_event_at_time_ms(hold_ms, select_all_leds, system, True, 0x00)
        return hold_ms + off_ms
    return hold_ms


def _schedule_alternating_firmware(controller, system, colors, interval_ms=500,
                                   fade_idx=0):
    """Alternate the whole ring through `colors` (each a RING_ALL_SAME frame) at
    `interval_ms`, IMMEDIATE by default. One step per color; the renderer repeats
    the array to fill the play duration. Returns the cycle ms."""
    controller.add_event_at_time_ms(0, set_color0, system, 0, 0, 0)
    t = 0
    for c in colors:
        r, g, b = c
        controller.add_event_at_time_ms(t, set_color1, system, r, g, b)
        controller.add_event_at_time_ms(t, set_fade_rate, system, fade_idx)
        controller.add_event_at_time_ms(t, select_all_leds, system, True, 0x07)
        t += interval_ms
    return t


def _schedule_blink_cycle(controller, system, color, on_ms, off_ms,
                          led_indices=None, fade_idx=0):
    """One firmware-style blink cycle: lit `on_ms` then off `off_ms`, IMMEDIATE
    by default. `led_indices=None` blinks the whole ring (RING_ALL_SAME); a list
    blinks only those LEDs (designated init). Records to a 2-step cycle the
    renderer repeats. Returns cycle_ms."""
    r, g, b = color
    controller.add_event_at_time_ms(0, set_color0, system, 0, 0, 0)
    controller.add_event_at_time_ms(0, set_color1, system, r, g, b)
    controller.add_event_at_time_ms(0, set_fade_rate, system, fade_idx)
    if led_indices is None:
        controller.add_event_at_time_ms(0, select_all_leds, system, True, 0x07)
        controller.add_event_at_time_ms(on_ms, select_all_leds, system, True, 0x00)
    else:
        for idx in led_indices:
            controller.add_event_at_time_ms(0, select_led, system, idx, True, 0x07)
            controller.add_event_at_time_ms(on_ms, select_led, system, idx, False, 0x00)
    return on_ms + off_ms


def _schedule_battery_cascade(controller, system, num_leds):
    """Firmware battery_25/50/75: white cascade of `num_leds` LEDs (0..N-1),
    each frame MEDIUM/500 ms, then 8 blink cycles toggling the LAST LED
    (off-frame first) at IMMEDIATE/300 ms while the rest stay lit. Records to
    (num_leds cascade + 16 blink) steps, matching the firmware count."""
    controller.add_event_at_time_ms(0, set_color0, system, 0, 0, 0)
    controller.add_event_at_time_ms(0, set_color1, system, *COLOR_WHITE)
    controller.add_event_at_time_ms(0, set_fade_rate, system, 4)  # MEDIUM
    controller.add_event_at_time_ms(0, global_off, system)
    # Cascade: light LED i at i*500 ms; each held 500 ms.
    for i in range(num_leds):
        controller.add_event_at_time_ms(i * 500, select_led, system, i, True, 0x07)
    last = num_leds - 1
    blink_start = num_leds * 500
    # 8 blink cycles: off (last LED dark) 300 ms, on 300 ms — IMMEDIATE.
    controller.add_event_at_time_ms(blink_start, set_fade_rate, system, 0)  # IMMEDIATE
    t = blink_start
    for _cycle in range(8):
        controller.add_event_at_time_ms(t, select_led, system, last, False, 0x00)
        controller.add_event_at_time_ms(t + 300, select_led, system, last, True, 0x07)
        t += 600
    return t  # blink_start + 8*600


def _dual_comet_varied(controller, system, color, trail_brightness):
    """Shared body for the two-comet, varied-speed pairing patterns
    (bluetooth/wifi). CW 3000 ms/rot, CCW 3400 ms/rot; Color0 dim, Color1 bright."""
    r, g, b = color
    dim = (int(r * trail_brightness), int(g * trail_brightness), int(b * trail_brightness))
    duration_ms = 12000
    controller.add_event_at_time_ms(0, set_fade_rate, system, 3)
    controller.add_event_at_time_ms(0, set_color0, system, *dim)
    controller.add_event_at_time_ms(0, set_color1, system, r, g, b)
    controller.add_event_at_time_ms(0, global_off, system)
    trail_length = 2
    for start, sign, rot in ((0, +1, 3000), (TOTAL_LEDS - 1, -1, 3400)):
        ms_per_led = max(50, (rot // TOTAL_LEDS) // 50 * 50)
        t = 0
        step = 0
        while t < duration_ms:
            led = (start + sign * step) % TOTAL_LEDS
            controller.add_event_at_time_ms(t, select_led, system, led, True, 0x07)
            if step >= 1:
                prev = (start + sign * (step - 1)) % TOTAL_LEDS
                controller.add_event_at_time_ms(t, select_led, system, prev, True, 0x00)
            if step >= trail_length:
                tail = (start + sign * (step - trail_length)) % TOTAL_LEDS
                controller.add_event_at_time_ms(t, select_led, system, tail, False, 0x00)
            step += 1
            t += ms_per_led
    return duration_ms + 1000


def _schedule_spin_firmware(controller, system, color, frame_ms=312, fade_idx=2):
    """One clockwise + counter-clockwise rotation: each frame lights exactly two
    LEDs (cw index k, ccw index 15-k) in `color`, FAST fade. Matches the
    firmware SPIN_FRAME sequence (bluetooth_pairing / wifi_pairing), including
    its exact 312 ms/frame — the recorder honors exact durations (no tick)."""
    r, g, b = color
    controller.add_event_at_time_ms(0, set_color0, system, 0, 0, 0)
    controller.add_event_at_time_ms(0, set_color1, system, r, g, b)
    controller.add_event_at_time_ms(0, set_fade_rate, system, fade_idx)
    controller.add_event_at_time_ms(0, global_off, system)
    t = 0
    for k in range(TOTAL_LEDS):
        cw, ccw = k, (TOTAL_LEDS - 1 - k) % TOTAL_LEDS
        # only the two current dots are lit each frame (single position, no trail)
        controller.add_event_at_time_ms(t, select_all_leds, system, False, 0x00)
        controller.add_event_at_time_ms(t, select_led, system, cw, True, 0x07)
        controller.add_event_at_time_ms(t, select_led, system, ccw, True, 0x07)
        t += frame_ms
    return t


_PERLIN_PERM = [
    151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225, 140,
    36, 103, 30, 69, 142, 8, 99, 37, 240, 21, 10, 23, 190, 6, 148, 247, 120,
    234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117, 35, 11, 32, 57, 177, 33,
    88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175, 74, 165, 71,
    134, 139, 48, 27, 166, 77, 146, 158, 231, 83, 111, 229, 122, 60, 211, 133,
    230, 220, 105, 92, 41, 55, 46, 245, 40, 244, 102, 143, 54, 65, 25, 63, 161,
    1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18, 169, 200, 196, 135, 130,
    116, 188, 159, 86, 164, 100, 109, 198, 173, 186, 3, 64, 52, 217, 226, 250,
    124, 123, 5, 202, 38, 147, 118, 126, 255, 82, 85, 212, 207, 206, 59, 227,
    47, 16, 58, 17, 182, 189, 28, 42, 223, 183, 170, 213, 119, 248, 152, 2, 44,
    154, 163, 70, 221, 153, 101, 155, 167, 43, 172, 9, 129, 22, 39, 253, 19, 98,
    108, 110, 79, 113, 224, 232, 178, 185, 112, 104, 218, 246, 97, 228, 251, 34,
    242, 193, 238, 210, 144, 12, 191, 179, 162, 241, 81, 51, 145, 235, 249, 14,
    239, 107, 49, 192, 214, 31, 181, 199, 106, 157, 184, 84, 204, 176, 115, 121,
    50, 45, 127, 4, 150, 254, 138, 236, 205, 93, 222, 114, 67, 29, 24, 72, 243,
    141, 128, 195, 78, 66, 215, 61, 156, 180,
]


_PERLIN_P = _PERLIN_PERM + _PERLIN_PERM  # doubled to 512 to avoid index wrap


def _perlin_fade(t):
    return t * t * t * (t * (t * 6 - 15) + 10)


def _perlin_lerp(a, b, t):
    return a + t * (b - a)


def _perlin_grad(h, x, y, z):
    h &= 15
    u = x if h < 8 else y
    v = y if h < 4 else (x if h in (12, 14) else z)
    return (u if (h & 1) == 0 else -u) + (v if (h & 2) == 0 else -v)


def _perlin_noise_3d(x, y, z):
    """Pure-Python 3D Perlin (Ken Perlin improved noise). Output ~[-1, 1].
    Drop-in replacement for Blender's mathutils.noise.noise() so the noise-driven
    patterns run headless. Deterministic (fixed permutation)."""
    X = int(math.floor(x)) & 255
    Y = int(math.floor(y)) & 255
    Z = int(math.floor(z)) & 255
    x -= math.floor(x)
    y -= math.floor(y)
    z -= math.floor(z)
    u = _perlin_fade(x)
    v = _perlin_fade(y)
    w = _perlin_fade(z)
    p = _PERLIN_P
    A = p[X] + Y
    AA = p[A] + Z
    AB = p[A + 1] + Z
    B = p[X + 1] + Y
    BA = p[B] + Z
    BB = p[B + 1] + Z
    return _perlin_lerp(
        _perlin_lerp(
            _perlin_lerp(_perlin_grad(p[AA], x, y, z),
                         _perlin_grad(p[BA], x - 1, y, z), u),
            _perlin_lerp(_perlin_grad(p[AB], x, y - 1, z),
                         _perlin_grad(p[BB], x - 1, y - 1, z), u), v),
        _perlin_lerp(
            _perlin_lerp(_perlin_grad(p[AA + 1], x, y, z - 1),
                         _perlin_grad(p[BA + 1], x - 1, y, z - 1), u),
            _perlin_lerp(_perlin_grad(p[AB + 1], x, y - 1, z - 1),
                         _perlin_grad(p[BB + 1], x - 1, y - 1, z - 1), u), v), w)


def build_ripple_green_steps(light_rgb=COLOR_LIGHT_GREEN, mid=25, max_level=80,
                             t_off=0.12, t_max=0.45, seed=None):
    """Build the green brightness-modulated ripple directly as RingStep[] from
    the ripple.py motion math — the reusable recipe for NEW snapshot-native
    (per-LED brightness) patterns. Returns (steps, duration_ms).

    Each keyed frame (100 ms) becomes one step: per LED, quantize the ripple
    level to {off, mid, max} brightness of `light_rgb`. Consecutive identical
    frames are merged (their durations summed). Every frame has at most two lit
    (color x brightness) pairs, so it passes the KTD2064 gate."""
    from ktd2064_ring_model import RingLed, RingStep, AGW_RINGLED_TRANSITION_IMMEDIATE
    _ripple = _import_ripple_math()
    drops = _ripple.make_drops(seed if seed is not None else _ripple.SEED)
    norm_max = _ripple.normalization_max(drops)
    frames = list(range(1, _ripple.LOOP_FRAMES + 1, _ripple.STEP))
    step_ms = int(1000 * _ripple.STEP / _ripple.FPS)  # 100 ms
    lr, lg, lb = light_rgb

    def frame_leds(t_s):
        leds = []
        for i in range(TOTAL_LEDS):
            raw = _ripple.drop_brightness(i, t_s, drops) / norm_max
            if raw < t_off:
                leds.append(RingLed(0, 0, 0, 0))
            elif raw < t_max:
                leds.append(RingLed(lr, lg, lb, mid))
            else:
                leds.append(RingLed(lr, lg, lb, max_level))
        return leds

    steps = []
    prev = None
    for f in frames:
        t_s = (f - 1) / _ripple.FPS
        leds = frame_leds(t_s)
        key = tuple((l.r, l.g, l.b, l.brightness) for l in leds)
        if prev is not None and key == prev[0]:
            prev[1].duration_ms += step_ms  # merge identical consecutive frame
            continue
        step = RingStep(leds=leds, transition=AGW_RINGLED_TRANSITION_IMMEDIATE,
                        duration_ms=step_ms)
        steps.append(step)
        prev = (key, step)
    total_ms = sum(s.duration_ms for s in steps)
    return steps, total_ms


# ============================================================================
# ZIRIS "APPROVED ANIMATIONS — ROUND 1"
# ============================================================================
# Ported from the 20 paste-in handoff snippets in
# "C:\Dev\Ziris Approved Animations - Round 1" (authored for the retired
# blender_ziris_led_integration_emissive.py host script; see that folder's
# README for the review feedback each one answers). Every pattern is the same
# mechanism: a per-LED normalized level(i, t) in 0..1, sampled every tick_ms,
# quantized against a threshold to a 0x07/0x00 selection bit and delta-filtered.
# Pure Frozen API — 2 palette colors + one global fade rate — so the fade
# engine renders every bit flip as a Color0<->Color1 crossfade. One seamless
# loop per schedule; the renderer/preview repeats it.


def _hash01(i, seed):
    """Deterministic pseudo-random 0..1 (same formula as the handoff files)."""
    x = math.sin(i * 127.1 + seed * 311.7) * 43758.5453
    return x - math.floor(x)


def _ring_distance(i, pos):
    d = abs(i - pos)
    return min(d, TOTAL_LEDS - d)


def _schedule_level_threshold(controller, system, level, color0_rgb, color1_rgb,
                              fade_rate_idx, loop_seconds, threshold=0.5,
                              tick_ms=100):
    """Shared Round-1 scheduler: set the 2-color palette + one global fade rate
    at t=0, then every tick_ms quantize each LED's level(i, t_s) against
    `threshold` into a selection bit, emitting select_led only on change."""
    loop_ms = loop_seconds * 1000.0
    controller.add_event_at_time_ms(0, set_color0, system, *color0_rgb)
    controller.add_event_at_time_ms(0, set_color1, system, *color1_rgb)
    controller.add_event_at_time_ms(0, set_fade_rate, system, fade_rate_idx)
    controller.add_event_at_time_ms(0, select_all_leds, system, True, 0x00)
    last_bits = [0x00] * TOTAL_LEDS
    t_ms = tick_ms
    while t_ms < loop_ms:
        t_s = t_ms / 1000.0
        for i in range(TOTAL_LEDS):
            bits = 0x07 if level(i, t_s) >= threshold else 0x00
            if bits != last_bits[i]:
                controller.add_event_at_time_ms(int(t_ms), select_led, system, i, True, bits)
                last_bits[i] = bits
        t_ms += tick_ms
    return int(loop_ms)


def _schedule_warble_kaleidoscope(controller, system, color0_rgb, color1_rgb,
                                  folds=4, inner_cycles=1, speed_hz=0.6):
    """Kaleidoscope fold: the ring is split into `folds` mirrored segments;
    alternate segments mirror their internal phase, so the wave reads as a
    symmetric breathing wobble, not a traveling wave. Loop 10 s."""
    def level(i, t_s):
        seg_len = TOTAL_LEDS / folds
        folded_pos = (i % seg_len) / seg_len
        if int(i // seg_len) % 2 == 1:
            folded_pos = 1.0 - folded_pos
        return 0.5 + 0.5 * math.sin(folded_pos * 2 * math.pi * inner_cycles
                                    - t_s * speed_hz * 2 * math.pi)
    return _schedule_level_threshold(controller, system, level,
                                     color0_rgb, color1_rgb,
                                     fade_rate_idx=3, loop_seconds=10.0)


def _schedule_braided_twist(controller, system, color0_rgb, color1_rgb,
                            twists=2, speed_hz=0.3):
    """Braided twist: two phase-opposed strands sweep the ring; each LED selects
    whichever strand dominates, so Color0/Color1 map directly onto the strands
    and the crossings come from selection-bit flips alone. Loop 10 s."""
    def level(i, t_s):
        strand = ((i / TOTAL_LEDS) * 2 * math.pi * twists
                  - t_s * speed_hz * 2 * math.pi)
        return 1.0 if math.cos(strand) >= 0.0 else 0.0
    return _schedule_level_threshold(controller, system, level,
                                     color0_rgb, color1_rgb,
                                     fade_rate_idx=3, loop_seconds=10.0)


def _schedule_wake_bloom(controller, system, color0_rgb, color1_rgb,
                         speed_hz=0.25, shimmer_speed=0.9):
    """Wake bloom (waiting): a slow global breath with a gentle 3-cycle spatial
    shimmer riding on top. Loop 8 s."""
    def level(i, t_s):
        base = 0.5 + 0.5 * math.sin(((t_s * speed_hz) % 1.0) * 2 * math.pi)
        shimmer = 0.15 * math.sin(2 * math.pi * (i / TOTAL_LEDS) * 3
                                  + t_s * shimmer_speed * 2 * math.pi)
        return max(0.0, min(1.0, base + shimmer))
    return _schedule_level_threshold(controller, system, level,
                                     color0_rgb, color1_rgb,
                                     fade_rate_idx=5, loop_seconds=8.0)


def _in_any_arc(i, pos, half_width, n_arcs):
    """True if LED i falls inside any of `n_arcs` equal arcs centered at
    pos, pos + N/n_arcs, ... (pos may be fractional)."""
    for a in range(n_arcs):
        c = (pos + a * TOTAL_LEDS / n_arcs) % TOTAL_LEDS
        if _ring_distance(i, c) < half_width:
            return True
    return False


def _hue_rgb(h):
    """Full-saturation, full-value hue (0..1 wraps) as an (r, g, b) 0-255 tuple."""
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, 1.0, 1.0)
    return (int(round(r * 255)), int(round(g * 255)), int(round(b * 255)))


BREATH_PERIOD_MS = 4000              # one full breath, in and out


BREATH_WHITE_RGB = (170, 170, 165)   # soft neutral white, well below 255


BREATH_FADE_IDX = 2                  # tau 125 ms — smooths BETWEEN the samples


BREATH_TICK_MS = 100                 # Color1 rewrite cadence (>= the 50 ms tick)


BLOOM_FADE_IDX = 1                   # tau 63 ms — crisp on/off edges in phase B


# mirrors ktd2064_blender_simulator.FADE_RATES (this module stays Blender-free)
FADE_TAU_MS = (31, 63, 125, 250, 500, 1000, 2000, 4000)


def _schedule_white_breath(controller, system, start_ms, duration_ms,
                           period_ms=BREATH_PERIOD_MS, tick_ms=BREATH_TICK_MS,
                           white_rgb=BREATH_WHITE_RGB, min_level=0.0,
                           start_at_peak=False):
    """Whole-ring white breathing on an explicit raised-cosine envelope, shared
    by `neutral_waiting_state` and phase A of the connect/pair flows so the two
    cannot drift apart.

    The envelope is driven directly rather than left to the fade engine: every
    LED stays selected on Color1 and Color1 itself is rewritten each tick to
    white scaled by

        level(t) = min_level + (1 - min_level) * (0.5 -/+ 0.5*cos(2*pi*phase))

    A raised cosine has zero slope at both ends, so the turnaround at full and at
    dark has no corner — that is what reads as smooth rather than pulsed. Letting
    the engine define the shape instead gives two glued exponentials (rise
    ~0.5*tau, fall ~4-6*tau) with a corner where they meet, even with the rate
    flipped mid-breath. The engine stays on but fast (index 2, tau 125 ms), where
    it now does something useful: smoothing between the 100 ms samples.

    Still Frozen API only — scaling brightness by rewriting Color1 is how the
    chip dims, so white at 30% is literally set_color1(51, 51, 49). The ring is
    uniform at every instant, so there is no per-LED work at all.

    `start_at_peak` starts the cosine at full instead of at dark, for joining
    onto something that is already lit. Callers must set the palette preamble
    (Color0, fade rate, select-all) themselves. Returns the end time in ms."""
    for k in range(int(round(duration_ms / float(tick_ms)))):
        t = k * tick_ms
        phase = (t % period_ms) / float(period_ms)
        cos_t = math.cos(2.0 * math.pi * phase)
        env = (0.5 + 0.5 * cos_t) if start_at_peak else (0.5 - 0.5 * cos_t)
        level = min_level + (1.0 - min_level) * env
        controller.add_event_at_time_ms(
            start_ms + t, set_color1, system,
            int(round(white_rgb[0] * level)),
            int(round(white_rgb[1] * level)),
            int(round(white_rgb[2] * level)))
    return int(start_ms + duration_ms)


def _schedule_connected_flow(controller, system, accent_rgb,
                             gap_rgb=COLOR_BLACK,
                             white_rgb=BREATH_WHITE_RGB,
                             breath_period_ms=BREATH_PERIOD_MS,
                             breath_cycles=3, process_ms=4000, connected_ms=1400,
                             n_arcs=3, gap_half_width=1.5, lit_half_width=None,
                             bloom_fade_idx=BLOOM_FADE_IDX, revolutions=1,
                             tick_ms=100):
    """Shared 3-phase connect/pair flow — 17.4 s at the defaults:

      A  0.0–12.0 s   soft white breathing, 3 x 4 s    (processing / pairing)
      B  12.0–16.0 s  wake-bloom trio in the accent    (processing / pairing)
      C  16.0–17.4 s  solid accent, held               (connected / paired)

    The phases are sequential, so the palette is just rewritten at each boundary
    — no time-slicing needed to stay inside the 2-color gate.

    Phase A is the SAME breath as `neutral_waiting_state`: same 4 s period, same
    raised-cosine envelope, same fade index 2, via the shared
    `_schedule_white_breath`. It is whole-ring, so it needs no per-LED work. It
    runs whole cycles and therefore ends dark, which is the hand-off into the
    bloom — phase B lights the ring in the accent from there.

    Phase B blooms UP into the accent (all LEDs on Color1) and then carves the
    rotating gaps into it; starting from 0x00 reads as a second fade-in rather
    than a bloom. Gap centres are snapped to whole LEDs — with float centres a
    gap straddling two LEDs covers 4 while a centred one covers 3, so the
    sections visibly changed size as they travelled. On 16 LEDs three sections
    cannot be exactly equidistant (16/3), so spacing lands on 5-5-6.

    revolutions must stay an INTEGER, and 1 is not arbitrary: 2 revolutions over
    4 s halves every dwell and the ring smears. Asserted below.

    CONTRAST. The gaps must reach full black and the lit sections full accent,
    so the SHORTEST run has to outlast the fade. 16/3 = 5.33 LEDs per section,
    so with 3-LED gaps the lit runs come out 2, 2, 3 — and a 2-LED run at
    4 LED/s holds only 500 ms. That is why phase B runs at fade index 1
    (tau 63 ms, 5*tau = 315 ms) rather than the index 2 the breath uses: at
    index 2 (625 ms) the two short sections were cut off mid-fade and never got
    fully bright, while the longer gaps did reach full black — the ring read as
    bright/dim rather than on/off. Index 1 also sharpens every edge, which is
    the same thing the separation wants.

    Equal 3-LED lit sections AND 3-LED gaps would need 18 LEDs; on 16 one of the
    two must be short, so the short one is a lit run and the fade is set to
    survive it.

    `lit_half_width` flips the geometry: instead of carving gaps out of a lit
    ring, it lights an arc of that half-width at each section centre and blanks
    everything else, which is the only way to get EQUAL lit sections (they come
    out odd-sized: 0.5 -> 1 LED, 1.0 -> 3 LEDs). A narrower lit run dwells for
    less time, so pair it with a faster `bloom_fade_idx` — the assert below
    checks the pairing whichever geometry is in use."""
    breath_total_ms = breath_period_ms * max(1, int(breath_cycles))
    total_ms = int(breath_total_ms + process_ms + connected_ms)

    speed_leds_per_s = revolutions * TOTAL_LEDS / (process_ms / 1000.0)
    # the shortest run on the ring — lit or dark — decides whether the fade
    # settles. Centres are snapped to whole LEDs, so `_ring_distance <= w`
    # covers floor(w) LEDs either side of the centre, plus itself.
    section_leds = math.floor(TOTAL_LEDS / float(n_arcs))
    if lit_half_width is not None:
        lit_leds = 2.0 * math.floor(lit_half_width) + 1.0
        shortest_run_leds = min(lit_leds, section_leds - lit_leds)
    else:
        gap_leds = 2.0 * math.floor(gap_half_width) + 1.0
        shortest_run_leds = min(gap_leds, section_leds - gap_leds)
    dwell_min_ms = (shortest_run_leds / speed_leds_per_s) * 1000.0
    required_ms = 5 * FADE_TAU_MS[bloom_fade_idx]
    assert dwell_min_ms >= required_ms, (
        f"shortest run is {shortest_run_leds:.0f} LEDs = {dwell_min_ms:.0f} ms < "
        f"5*tau at fade index {bloom_fade_idx} ({required_ms} ms); that run would "
        f"not reach full brightness/black — use a faster bloom_fade_idx, slow the "
        f"sweep, or widen the sections."
    )

    # ---------------- phase A: soft white breath ----------------
    # Color0 is unused here — every LED sits on Color1 and the envelope comes
    # from rewriting Color1, exactly as in neutral_waiting_state.
    controller.add_event_at_time_ms(0, set_color0, system, 0, 0, 0)
    controller.add_event_at_time_ms(0, set_fade_rate, system, BREATH_FADE_IDX)
    controller.add_event_at_time_ms(0, set_color1, system, 0, 0, 0)
    controller.add_event_at_time_ms(50, select_all_leds, system, True, 0x07)
    _schedule_white_breath(controller, system, 0, breath_total_ms,
                           period_ms=breath_period_ms, tick_ms=tick_ms,
                           white_rgb=white_rgb)

    # ---------------- phase B: accent wake-bloom trio ----------------
    # The breath ended dark, so writing the accent into Color1 (which every LED
    # is already selected onto) IS the bloom — same 125 ms tau the old
    # 0x00 -> 0x07 bloom used. Color0 is what the gaps show: black, so the three
    # lit sections are separated by genuinely blank ring rather than by a dimmer
    # shade of the same hue.
    b_start, b_end = int(breath_total_ms), int(breath_total_ms + process_ms)
    controller.add_event_at_time_ms(b_start, set_color0, system, *gap_rgb)
    controller.add_event_at_time_ms(b_start, set_color1, system, *accent_rgb)
    controller.add_event_at_time_ms(b_start, set_fade_rate, system, bloom_fade_idx)
    controller.add_event_at_time_ms(b_start + 50, select_all_leds, system, True, 0x07)

    def _gap_centres(pos):
        base = int(round(pos)) % TOTAL_LEDS
        spacing = TOTAL_LEDS / float(n_arcs)
        return [(base + int(round(k * spacing))) % TOTAL_LEDS for k in range(n_arcs)]

    def _is_lit(i, pos):
        if lit_half_width is not None:
            return any(_ring_distance(i, c) <= lit_half_width for c in _gap_centres(pos))
        return not any(_ring_distance(i, c) <= gap_half_width for c in _gap_centres(pos))

    # matches the bloom-up state above, so the first tick only emits the gaps
    last_bits = [0x07] * TOTAL_LEDS
    t_ms = b_start + 100
    while t_ms <= b_end:
        pos = (((t_ms - b_start) / 1000.0) * speed_leds_per_s) % TOTAL_LEDS
        for i in range(TOTAL_LEDS):
            bits = 0x07 if _is_lit(i, pos) else 0x00
            if bits != last_bits[i]:
                controller.add_event_at_time_ms(int(t_ms), select_led, system, i, True, bits)
                last_bits[i] = bits
        t_ms += tick_ms

    # ---------------- phase C: solid accent, held ----------------
    controller.add_event_at_time_ms(b_end, set_fade_rate, system, 3)   # tau 250 ms
    controller.add_event_at_time_ms(b_end + 50, select_all_leds, system, True, 0x07)
    return total_ms


# Destination colors (sRGB 0-255). These mirror led_ring_patterns.COLOR_RED /
# COLOR_AMBER, which mirror the firmware RGB_* macros — keep all in sync.
# NOTE the porting notes say amber (255, 76, 0); that was the PRE-update value
# ("was 255,76,0" in the palette table) — the firmware macro is now (255,126,0),
# and preview == device requires the macro value.
ARM_AWAY_RED = (255, 0, 0)      # RGB_RED


ARM_HOME_AMBER = (255, 126, 0)  # RGB_AMBER


STANDBY_GREEN = (0, 255, 0)     # RGB_GREEN


# ============================================================================
# RIPPLE MOTION MATH LOADER (shared by listening + the ripple patterns)
# ============================================================================


def _import_ripple_math():
    """Import the pure ripple motion math (make_drops / drop_brightness /
    normalization_max). Prefers a repo-root `ripple.py` (the designer's own copy,
    if present); otherwise falls back to the vendored `ripple_reference.py` under
    tests/fixtures, which ships with the repo. Raises only if neither exists."""
    import os
    import sys
    here = os.path.dirname(os.path.abspath(__file__))
    fixtures = os.path.join(here, "tests", "fixtures")
    if fixtures not in sys.path:
        sys.path.append(fixtures)
    try:
        import ripple as _ripple                # repo root: designer's own math
        return _ripple
    except ImportError:
        pass
    try:
        import ripple_reference as _ripple      # vendored fallback (tests/fixtures)
        return _ripple
    except ImportError as exc:
        raise RuntimeError(
            "ripple motion math not found: need ripple.py (make_drops / "
            "drop_brightness / normalization_max) at the repo root, or "
            "tests/fixtures/ripple_reference.py."
        ) from exc


def _ripple_supports_tuning(_ripple):
    """True if this ripple.py accepts the listening tuning kwargs
    (n_drops / ripple_speed / decay_rate / pulse_w). The reference ripple.py
    has narrower signatures; the ziris runtime shipped an extended one."""
    import inspect
    try:
        db = inspect.signature(_ripple.drop_brightness).parameters
        md = inspect.signature(_ripple.make_drops).parameters
    except (TypeError, ValueError):
        return False
    return ("ripple_speed" in db and "n_drops" in md)


# ============================================================================
# LISTENING (ziris voice-assistant feedback)
# ============================================================================


def _schedule_spin_solid_fade(controller, system, color, keep_solid=False,
                              spin_rotation_ms=2200, num_spin_rotations=2,
                              spin_trail_length=5, solid_hold_ms=3000,
                              fade_rate_spin=0, fade_rate_solid=4,
                              fade_rate_out=3, fade_out_ms=1500):
    """Shared Arm Away / Arm Home engine (port of pattern_spin_solid_fade).
    Three phases, ~9.4 s at the defaults:

      1. SPIN  — a SINGLE comet rotates CLOCKWISE twice around the ring in the
                 destination color: bright head, dim trail. ~2.4 s per lap.
      2. SOLID — all LEDs snap on together at full destination color, held 3 s.
      3. FADE  — everything fades exponentially to off (~250 ms TC). Skipped
                 when keep_solid=True (persistent armed indicator).

    Hard rules from the spec (arm_states_porting_notes.md): ONE comet only —
    exactly three select_led calls per step (head bright, prev dim, oldest tail
    off); an earlier dual-comet version read as two crossing comets and was the
    #1 bug. Clockwise on the device face: increasing LED index is clockwise
    (measured in Arlo_Ziris.blend — LED angles decrease with index), so the head
    advances +1. Spin color = DESTINATION color, never the previous state's.

    The comet gradient is the 2-color trick: Color1 = head (100%), Color0 =
    trail (30%); the trail is HELD at 30% by the selection registers, and only
    the tail-off decay uses the fade engine.

    fade_rate_spin=0 (31 ms TC) is deliberate and differs from the notes'
    original 3: the head holds full brightness for only one step (~150 ms), and
    at rate 3 (250 ms TC) it only ever reached ~45% — dim head smeared into the
    trail. Rate 0 snaps it to ~99% within its step. One global fade rate is a
    hardware constraint: a full-bright head AND a long soft tail-off are not
    simultaneously available; rate 1 (63 ms, head ~91%) is the softer compromise.

    step quantization: step_ms snaps to the 50 ms firmware tick —
    2200/16 = 137.5 -> 150 ms, so a lap really takes ~2.4 s, not 2.2 (expected,
    per the notes)."""
    dim = tuple(int(round(c * 0.30)) for c in color)
    step_ms = max(50, int(round(spin_rotation_ms / TOTAL_LEDS / 50.0)) * 50)
    steps = num_spin_rotations * TOTAL_LEDS

    controller.add_event_at_time_ms(0, set_color0, system, *dim)
    controller.add_event_at_time_ms(0, set_color1, system, *color)
    controller.add_event_at_time_ms(0, set_fade_rate, system, fade_rate_spin)
    controller.add_event_at_time_ms(0, select_all_leds, system, False, 0x00)

    # --- Phase 1: single clockwise comet ---
    head = 0
    history = []
    for step in range(steps):
        t = step * step_ms
        controller.add_event_at_time_ms(t, select_led, system, head, True, 0x07)
        if history:
            controller.add_event_at_time_ms(t, select_led, system,
                                            history[-1], True, 0x00)
        if len(history) >= spin_trail_length:
            controller.add_event_at_time_ms(t, select_led, system,
                                            history[-spin_trail_length], False, 0x00)
        history.append(head)
        head = (head + 1) % TOTAL_LEDS     # +1 = clockwise on the device face
    spin_end = steps * step_ms

    # --- Phase 2: solid ---
    solid_at = spin_end + 100
    controller.add_event_at_time_ms(solid_at, set_fade_rate, system, fade_rate_solid)
    controller.add_event_at_time_ms(solid_at, select_all_leds, system, True, 0x07)
    if keep_solid:
        return solid_at + solid_hold_ms

    # --- Phase 3: fade to off (the chip's exponential engine does the ramp) ---
    fade_at = solid_at + solid_hold_ms
    controller.add_event_at_time_ms(fade_at, set_fade_rate, system, fade_rate_out)
    controller.add_event_at_time_ms(fade_at, select_all_leds, system, False, 0x00)
    return fade_at + fade_out_ms
