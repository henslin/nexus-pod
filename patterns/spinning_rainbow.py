"""spinning_rainbow — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Continuous hue gradient sweeps the ring, palette walks the wheel; loop 12 s.")


def schedule_spinning_rainbow(controller, system, loop_seconds=12.0, tick_ms=100,
                              revolutions=6, hue_offset=0.25, arc_fraction=0.5,
                              fade_rate_idx=5):
    """Spinning rainbow: a continuous color gradient sweeps around the ring while
    the palette walks the color wheel, so the ring travels the whole spectrum
    over the loop. Loop 12 s.

    WHAT THE HARDWARE ALLOWS. A literal rainbow — the full spectrum lit around
    the ring at once — cannot render. The gate permits 2 unique colors per frame
    and REJECTS a third, so no frame can ever hold red+yellow+green+blue at the
    same instant. This is the closest the chip can come, and it is not a
    consolation prize: it is the mechanism that gives every eye-candy pattern in
    this catalog its multi-hue look.

    HOW THE CONTINUOUS GRADIENT HAPPENS. Two things run at once:

      1. A selection edge sweeps the ring, flipping each LED from Color0 to
         Color1 (and back) as it passes. Adjacent LEDs therefore flip at
         DIFFERENT times — 125 ms apart at the defaults.
      2. The fade rate is set deliberately SLOW relative to that spacing
         (index 5, tau 1000 ms, vs 125 ms between flips). So an LED takes far
         longer to travel between the two palette colors than the edge takes to
         reach the next LED.

    The result is that at any instant every LED sits at a different point along
    its Color0 -> Color1 interpolation, and the ring shows a smooth continuous
    ramp of intermediate hues rather than two blocks. Roughly 8 LEDs are always
    mid-fade. This is the one place in the catalog where NOT settling is the
    point — the usual 5*tau dwell rule is inverted, and the assert below enforces
    the opposite: tau must be several flip-intervals LONG, not short.

    Meanwhile both palette colors advance one full turn of the wheel per loop,
    so the ring shows a moving 90-degree slice of the spectrum and travels the
    whole wheel over the loop.

    WHY hue_offset CANNOT JUST BE WIDENED TO A FULL RAINBOW. The fade engine
    interpolates in RGB, so the blend is a straight LINE between the two palette
    colors, and that line only follows the color wheel for hues about 60 deg
    apart. Wider offsets cut across the RGB cube and the middle of the gradient
    degrades — at 180 deg (red<->cyan) the midpoint is (128,128,128), literally
    grey. Measured on the rendered ring (fade engine simulated, worst case over
    the loop):

        offset   dimmest LED   lowest saturation
        60 deg     172/255          0.66
        90 deg     154/255          0.57      <- default: widest good-looking arc
        120 deg    139/255          0.39      washing out

    90 deg is the chosen trade: a visibly wider span of the spectrum than 60 deg
    while staying colorful. Push to 120 deg only if span matters more than
    saturation. (These are worse than the ideal-blend math predicts because the
    palette keeps moving while each LED is still fading, so LEDs chase a moving
    target and drift slightly off the pure blend line.)

    NOTE ON THE REFERENCE IMAGE. A full simultaneous ROYGBIV around the ring —
    the marketing look — needs ~16 hues at once and is NOT renderable here at any
    setting; the gate would drop every such frame. This is the closest the chip
    can come.

    Every LED is lit at all times; this pattern has no dark state.

    NOT FIRMWARE-PALETTE. The hues are generated, so they do not map to the
    RGB_* macros; exporting this emits raw RGB literals. Every frame is still
    gate-valid and submittable, but it is a preview/demo pattern rather than a
    catalog candidate — a shipping version would need its hues pinned to macros."""
    loop_ms = loop_seconds * 1000.0
    speed_leds_per_s = revolutions * TOTAL_LEDS / loop_seconds
    arc_leds = int(round(arc_fraction * TOTAL_LEDS))

    # INVERTED dwell rule: the gradient exists only while LEDs are mid-fade, so
    # tau must be LONG compared with the gap between neighbouring LEDs flipping.
    flip_interval_ms = 1000.0 / speed_leds_per_s
    tau_ms = FADE_TAU_MS[fade_rate_idx]
    leds_mid_fade = tau_ms / flip_interval_ms
    assert leds_mid_fade >= 3.0, (
        f"tau {tau_ms} ms is only {leds_mid_fade:.1f} flip-intervals "
        f"({flip_interval_ms:.0f} ms each); fewer than ~3 LEDs would be mid-fade and "
        f"the ring would read as two hard bands instead of a gradient — use a slower "
        f"fade index or spin faster."
    )

    controller.add_event_at_time_ms(0, set_fade_rate, system, fade_rate_idx)
    controller.add_event_at_time_ms(0, set_color0, system, *_hue_rgb(0.0))
    controller.add_event_at_time_ms(0, set_color1, system, *_hue_rgb(hue_offset))
    controller.add_event_at_time_ms(0, select_all_leds, system, True, 0x00)

    last_bits = [0x00] * TOTAL_LEDS
    t_ms = tick_ms
    while t_ms < loop_ms:
        t_s = t_ms / 1000.0
        # both palette hues advance one full turn of the wheel per loop
        h = t_s / loop_seconds
        controller.add_event_at_time_ms(int(t_ms), set_color0, system, *_hue_rgb(h))
        controller.add_event_at_time_ms(int(t_ms), set_color1, system,
                                        *_hue_rgb(h + hue_offset))
        # ...while the selection edge sweeps. The edge is snapped to a whole LED
        # and the arc counted FORWARD from it: a centre-symmetric arc can only
        # cover an ODD number of LEDs, so an even half-and-half split is
        # impossible that way, and an unsnapped edge makes the arc change size as
        # it travels.
        edge = int(round((t_s * speed_leds_per_s) % TOTAL_LEDS)) % TOTAL_LEDS
        for i in range(TOTAL_LEDS):
            bits = 0x07 if ((i - edge) % TOTAL_LEDS) < arc_leds else 0x00
            if bits != last_bits[i]:
                controller.add_event_at_time_ms(int(t_ms), select_led, system, i, True, bits)
                last_bits[i] = bits
        t_ms += tick_ms
    return int(loop_ms)
