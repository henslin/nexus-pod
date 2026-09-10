"""spinning_rainbow_quad — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = True
DESCRIPTION = ("Ordered ROYGBIV walking clockwise, per-driver palettes (PREVIEW "
                      "ONLY — exceeds the ring-wide 2-color gate; needs a per-driver "
                      "gate to ship).")


def schedule_spinning_rainbow_quad(controller, system, loop_seconds=12.0,
                                   revolutions=6, slot_ms=50,
                                   hue_offset=1.0 / 3.0,
                                   clockwise=True, fade_rate_idx=3):
    """Ordered walking rainbow, per-driver palettes — RENDER_ONLY.

    ROYGBIV in SPATIAL ORDER around the ring, the whole arrangement rotating
    clockwise. At any instant the ring covers 2*hue_offset of the wheel (240
    degrees nominal at the 1/3 default, ~265 rendered) as one monotone hue ramp:
    driver 0 (LEDs 1-8) spans [h, h+off], driver 1 (LEDs 9-16) continues
    [h+off, h+2*off], one wrap seam where the ends meet. Measured on the
    fade-engine simulation: 15/15 neighbouring LED pairs in spectral order.

    HOW EACH LED HOLDS ITS OWN HUE (the earlier sweep could not do this — it
    dragged every LED across its whole slice and back, mirroring the spectrum).
    A chip offers only anchors Color0/Color1 and a binary per-LED selection, but
    the selection can be DITHERED: LED j's bit toggles between the anchors with
    duty cycle (j%8 + 0.5)/8, error-diffused over 50 ms slots. With tau
    (250 ms) long against the slot, the fade engine low-pass filters the
    toggling and the LED settles at the duty-weighted point along the
    Color0->Color1 blend — a STABLE per-LED fraction, monotone in j, ripple only
    a few percent. This is real chip behavior (commands are 50 ms apart, one
    global fade rate, nothing but select_led), just used as a DAC.

    ROTATION comes from the anchors, not the duties: all four anchor hues walk
    the wheel `revolutions` times per loop, so the fixed spatial ramp slides
    through the spectrum and the visible rainbow walks the circle — one visual
    revolution per wheel cycle, 3 s each at the defaults (4 revs / 12 s). The
    hue walk runs NEGATIVE for clockwise: in Arlo_Ziris.blend the LED angles
    decrease as the index rises (LED1 at -103 deg, LED2 at -127, ...), so
    increasing index is clockwise from above, the ramp increases with index,
    and red lands at ramp = -h — advancing h backward moves red toward higher
    index. Set clockwise=False (or re-measure if the ring is re-rigged) to flip.

    SPIN SPEED vs SATURATION is a real coupling, measured: every LED chases a
    target moving around the wheel, and when the fade lags the walk the ring
    desaturates (attenuation ~1/sqrt(1+(w*tau)^2)). So faster spin needs a
    SHORTER tau — but a shorter tau also filters the 50 ms dither less (more
    ripple). The measured sweet spots:

        revs tau_idx  s/rev   span    min-sat
          1    5      12.0   8.7/12   0.51    original: too slow to read as spin
          4    3       3.0   7.6/12   0.49    <- default
          6    3       2.0   7.6/12   0.47    faster, similar quality
          3    5       4.0   8.8/12   0.37    slow fade + fast walk = washed

    Keep `revolutions` integer for a seamless loop. hue_offset trade (at the
    defaults): 0.25 -> vivid but narrower span; 0.40 -> wider but washes white.

    WHY RENDER_ONLY. Per-driver palettes are a legal targeted I2C write on real
    chips, but the CURRENT firmware renderer gates 2 unique colors ACROSS ALL 16
    LEDs, so agw_ringled_play would reject every frame. Previews truthfully (the
    simulator models both chips); hard-blocked from export; shippable only if
    the firmware gate is relaxed to per-driver (a CMFW-27866 firmware question).

    Every LED is lit at all times; there is no dark state."""
    assert slot_ms >= 50, "slot_ms below the 50 ms firmware tick"
    loop_ms = loop_seconds * 1000.0
    half = TOTAL_LEDS // 2

    controller.add_event_at_time_ms(0, set_fade_rate, system, fade_rate_idx)
    # per-LED duty: LED i sits (i%8 + 0.5)/8 of the way along its driver's slice
    duty = [((i % half) + 0.5) / half for i in range(TOTAL_LEDS)]
    err = [0.0] * TOTAL_LEDS
    last_bits = [None] * TOTAL_LEDS

    t_ms = 0
    while t_ms < loop_ms:
        t_s = t_ms / 1000.0
        # anchors walk the wheel `revolutions` times per loop; negative =
        # clockwise (see docstring)
        h = t_s * revolutions / loop_seconds
        if clockwise:
            h = -h
        for d in (0, 1):
            controller.add_event_at_time_ms(int(t_ms), set_driver_color0, system,
                                            d, *_hue_rgb(h + d * hue_offset))
            controller.add_event_at_time_ms(int(t_ms), set_driver_color1, system,
                                            d, *_hue_rgb(h + (d + 1) * hue_offset))
        # error-diffused duty dither: accumulate, fire a Color1 slot on carry
        for i in range(TOTAL_LEDS):
            err[i] += duty[i]
            if err[i] >= 1.0:
                err[i] -= 1.0
                bits = 0x07
            else:
                bits = 0x00
            if bits != last_bits[i]:
                controller.add_event_at_time_ms(int(t_ms), select_led, system,
                                                i, True, bits)
                last_bits[i] = bits
        t_ms += slot_ms
    return int(loop_ms)
