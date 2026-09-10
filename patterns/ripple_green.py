"""ripple_green — registered LED-ring pattern (see pattern_common.py)."""

import math

from pattern_common import *          # noqa: F401,F403
from pattern_common import (          # noqa: F401
    _PERLIN_P, _PERLIN_PERM, _dual_comet_varied, _hash01, _hue_rgb, _import_ripple_math, _in_any_arc, _perlin_fade, _perlin_grad, _perlin_lerp, _perlin_noise_3d, _ring_distance, _ripple_supports_tuning, _schedule_alternating_firmware, _schedule_battery_cascade, _schedule_blink_cycle, _schedule_braided_twist, _schedule_connected_flow, _schedule_level_threshold, _schedule_solid_firmware, _schedule_spin_firmware, _schedule_spin_solid_fade, _schedule_wake_bloom, _schedule_warble_kaleidoscope, _schedule_white_breath,
)

DURATION_MS = None
RENDER_ONLY = False
DESCRIPTION = ("Green raindrop ripple via per-LED brightness (firmware ripple style).")
BUILD_STEPS = build_ripple_green_steps


def schedule_ripple_green(controller, system):
    """Snapshot-native GREEN ripple — the brightness-modulated ripple matching
    the firmware's approach (RGB_LIGHT_GREEN at RIPPLE_MID=25 / RIPPLE_MAX=80).

    Unlike schedule_ripple_blue_white (which encodes level as a HUE crossfade via
    the fade engine), this uses the snapshot firmware's PER-LED BRIGHTNESS field:
    one green color at two brightness levels. It is authored DIRECTLY as
    RingStep[] (see build_ripple_green_steps) and played through the step player
    (led_ring_core.schedule_steps), which drives the SAME Frozen API the
    command-stream patterns use — so it previews in Blender and records for
    export identically, exactly as the device renders it. This is the reference
    recipe for new per-LED-brightness patterns."""
    steps, _total = build_ripple_green_steps()
    return schedule_steps(controller, system, steps)
