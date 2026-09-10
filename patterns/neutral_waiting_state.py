"""neutral_waiting_state — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = 15000
RENDER_ONLY = False
DESCRIPTION = ("3 s wake-up fade, 2 s hold, then whole-ring white cosine breathing (idle).")


def schedule_neutral_waiting_state(controller, system, wake_ms=3000,
                                   hold_ms=2000, period_ms=BREATH_PERIOD_MS,
                                   breaths=3, tick_ms=BREATH_TICK_MS,
                                   white_rgb=BREATH_WHITE_RGB, min_level=0.0):
    """Neutral / waiting: a 3 s wake-up fade from dark to full, a 2 s hold at
    full, then whole-ring soft white breathing, on and off. No color, no
    direction, no implied urgency. 3 s wake + 2 s hold + 10 s breath = 15 s.

    The breath itself is `_schedule_white_breath` — the SAME helper phase A of
    the connect/pair flows uses, so the two cannot drift apart. See it for why
    the envelope is driven directly instead of by the fade engine.

    min_level 0.0 breathes fully off, which can read as "did it switch off?"
    rather than "it is waiting"; 0.04-0.08 keeps the ring alive without drawing
    the eye. Left at 0.0 because that is the version that was reviewed.

    WAKE-IN (first wake_ms). The ring starts dark and rises to full on a cosine
    HALF-cycle, 0.5 - 0.5*cos(pi*u). That is the same curve family as the
    breath, so the wake reads as one long first inhale rather than a separate
    intro clip. Both ends have zero slope: it leaves darkness without a jolt and
    arrives at full without a corner. A linear ramp instead lands with a visible
    kink where it stops, and an exponential (letting the fade engine do it) is
    the very shape this pattern exists to avoid.

    HOLD (next hold_ms). The ring then sits at full for 2 s before the breath
    begins, so the wake lands and settles instead of turning around the instant
    it arrives. Level is constant here, so the recorder coalesces the whole hold
    into ONE step — it costs a single frame, not 20.

    The breath starts at the PEAK, not at zero — 0.5 + 0.5*cos(2*pi*p) — so both
    the wake and the hold hand straight off into the first exhale with no
    discontinuity (every side of both joins is at level 1.0, and the wake and
    breath each have zero slope there, so the hold adds no corners).

    Ending dark keeps the loop seamless: the breath runs breaths - 0.5 periods,
    so it terminates at a trough, exactly where the wake-in begins. Counting the
    wake as the first inhale, breaths=3 still gives 3 inhales and 3 exhales;
    total is wake_ms + hold_ms + (breaths - 0.5) * period_ms = 15.0 s at the
    defaults."""
    breath_ms = int((breaths - 0.5) * period_ms)
    breath_start_ms = wake_ms + hold_ms
    total_ms = int(breath_start_ms + breath_ms)

    # Color0 is never shown — every LED sits on Color1 for the whole pattern.
    controller.add_event_at_time_ms(0, set_color0, system, 0, 0, 0)
    controller.add_event_at_time_ms(0, set_fade_rate, system, BREATH_FADE_IDX)
    controller.add_event_at_time_ms(0, set_color1, system, 0, 0, 0)
    controller.add_event_at_time_ms(50, select_all_leds, system, True, 0x07)

    # wake-in: dark -> full on a cosine half-cycle (zero slope at both ends)
    for k in range(int(round(wake_ms / float(tick_ms)))):
        t = k * tick_ms
        level = 0.5 - 0.5 * math.cos(math.pi * (t / float(wake_ms)))
        controller.add_event_at_time_ms(
            t, set_color1, system,
            int(round(white_rgb[0] * level)),
            int(round(white_rgb[1] * level)),
            int(round(white_rgb[2] * level)))

    # hold at full — one event; the level is constant until the breath starts
    controller.add_event_at_time_ms(wake_ms, set_color1, system, *white_rgb)

    _schedule_white_breath(controller, system, breath_start_ms, breath_ms,
                           period_ms=period_ms, tick_ms=tick_ms,
                           white_rgb=white_rgb, min_level=min_level,
                           start_at_peak=True)
    return total_ms


# ============================================================================
# PATTERN REGISTRY
# ============================================================================
