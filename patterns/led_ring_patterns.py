"""
led_ring_patterns.py — the pattern REGISTRY (catalog assembly only)
===================================================================
Every pattern lives in its own module under patterns/ (one file per pattern,
shareable on its own), with the shared vocabulary/engines in pattern_common.py.
This module assembles them into the ordered PATTERNS catalog that preview
(run_ring/run_harpy/run_ziris), export (export_patterns), and the test suite
consume — the external API (PATTERNS, get_pattern, list_patterns, PatternSpec)
is unchanged from the old monolithic layout.

Each patterns/<name>.py defines schedule_<name>(controller, system) -> total_ms
plus its metadata (DURATION_MS / RENDER_ONLY / DESCRIPTION, optional
BUILD_STEPS). To add a pattern: drop the file in patterns/ and add its name to
_PATTERN_ORDER below (order is preserved for catalog listings and --all
export). The rules in CLAUDE.md ("When adding or changing patterns") still
apply — Frozen API only, gate-safe, colors from the firmware palette.

Back-compat: the public vocabulary of pattern_common (COLOR_*, the generic
engines, build_ripple_green_steps, ...) is re-exported here so existing
callers (export_patterns --green-ripple, tests) keep working.
"""

import importlib
from dataclasses import dataclass
from typing import Callable, Dict, List, Optional, Tuple

from pattern_common import *                  # noqa: F401,F403 — back-compat re-export
from pattern_common import build_ripple_green_steps   # noqa: F401 — explicit: export_patterns uses it


REGISTRY_DOC = "assembled from patterns/<name>.py; see module docstring"


@dataclass
class PatternSpec:
    """Metadata + scheduler for one pattern.

    `schedule(controller, system) -> total_ms` drives BOTH preview and export.

    `build_steps() -> (RingStep[], duration_ms)` is optional. When present, EXPORT
    uses these author-provided snapshots directly instead of recording the command
    stream (required for PER-LED-BRIGHTNESS patterns like the green ripple).
    Preview still runs `schedule`, so preview == device either way.

    `duration_ms` mirrors the firmware header where a known value exists; None
    means "loop until cleared" (INFINITE). `render_only` hard-blocks firmware
    export (see tests/test_patterns.py::
    test_render_only_is_exactly_the_documented_exceptions for the exception
    list)."""
    name: str
    schedule: Callable
    duration_ms: Optional[int] = None
    render_only: bool = False
    description: str = ""
    build_steps: Optional[Callable] = None


# Ordered catalog. Order is meaningful (listings, --all export) and matches the
# historical monolith order.
_PATTERN_ORDER = [
    "booting_up",
    "power_on_success",
    "battery_low",
    "battery_25",
    "battery_50",
    "battery_75",
    "battery_100",
    "bluetooth_pairing",
    "bluetooth_pairing_varied_speed",
    "bluetooth_pairing_dual_color",
    "bluetooth_success",
    "bluetooth_failed",
    "bluetooth_critical",
    "wifi_pairing",
    "wifi_pairing_varied_speed",
    "wifi_success",
    "wifi_failed",
    "wifi_critical",
    "device_offline",
    "factory_reset",
    "firmware_update",
    "firmware_update_dual_comet",
    "firmware_update_circular_fill",
    "firmware_update_comet",
    "firmware_update_dual_comet_varied_speed",
    "firmware_update_success",
    "firmware_update_failed",
    "alarm_sos",
    "spotlight_deterrence",
    "ripple_blue_white",
    "ripple_green",
    "arm_away",
    "arm_home",
    "standby",
    "listening",
    "soft_bloom_warble",
    "traveling_ribbon",
    "perlin_noise_flicker",
    "bubble_simmer",
    "aurora_interference_curtain",
    "plasma_drift",
    "loading",
    "warble_kaleidoscope_red",
    "warble_kaleidoscope_amber",
    "warble_kaleidoscope_green",
    "warble_kaleidoscope_blue",
    "braided_twist_green",
    "braided_twist_red",
    "ribbon_phase_warp_red",
    "cellular_automaton_green",
    "flocking_drift_connection_green",
    "tidal_modulation_loading_green",
    "resonant_ping_decay_occupancy_green",
    "pendulum_swing_deterrence_red",
    "strobe_pulsing_lattice_red",
    "wake_bloom_waiting_blue_navy_cobalt",
    "wake_bloom_waiting_blue_steel_ice",
    "wake_bloom_trio_gaps_green",
    "mic_level_jitter_listening_blue",
    "quantum_tunneling_speaking_blue",
    "speaking_response_waveform_blue",
    "utterance_loudness_envelope_blue",
    "voiceprint_shimmer_blue",
    "bluetooth_connected_flow",
    "wifi_pairing_flow_green",
    "connected_flow_purple",
    "spinning_rainbow",
    "spinning_rainbow_quad",
    "neutral_waiting_state",
]

PATTERNS: Dict[str, PatternSpec] = {}

for _name in _PATTERN_ORDER:
    _mod = importlib.import_module(f"patterns.{_name}")
    PATTERNS[_name] = PatternSpec(
        name=_name,
        schedule=getattr(_mod, f"schedule_{_name}"),
        duration_ms=getattr(_mod, "DURATION_MS", None),
        render_only=getattr(_mod, "RENDER_ONLY", False),
        description=getattr(_mod, "DESCRIPTION", ""),
        build_steps=getattr(_mod, "BUILD_STEPS", None),
    )


def list_patterns():
    """Return the ordered list of pattern names."""
    return list(PATTERNS.keys())


def get_pattern(name: str) -> PatternSpec:
    """Look up a pattern by registry name.

    Tolerates a leading `pattern_` prefix so a handoff FILE name
    (`pattern_warble_kaleidoscope_red.py`) resolves to its registry name
    (`warble_kaleidoscope_red`). A genuinely unknown name still raises KeyError.
    """
    if name in PATTERNS:
        return PATTERNS[name]
    if name.startswith("pattern_") and name[len("pattern_"):] in PATTERNS:
        return PATTERNS[name[len("pattern_"):]]
    raise KeyError(f"unknown pattern {name!r}; see list_patterns()")
