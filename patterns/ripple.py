"""
================================================================================
STYLE_Ripple  —  Harpy LED-ring animation  —  DEV HANDOFF
================================================================================
Effect : Drops land at random ring positions and ripple SYMMETRICALLY outward
         in both directions, fading as they expand. Multiple ripples overlap.
         No spin / no preferred direction.

Scene  : "Harpy" (Blender 5.1, Cycles). 16-LED ring, each ring index has two
         sub-emitters (_1/_2) => 32 driven materials. Brightness reads on the
         mesh EMISSION node ("Emission": inputs[0]=Color RGBA, inputs[1]=Strength).

Loop   : 720 frames @ 60 fps = 12.0 s, perfectly seamless (drop phases wrap).
Keying : every 6th frame (100 ms) — a multiple of the 50 ms firmware tick.

HARDWARE / FIRMWARE CONTRACT (KTD2064-safe):
  - 16 logical LEDs around the ring (ring index 0..15, wrap-around distance).
  - 2 color registers + single global fade rate: this style uses ONE hue ramp
    (sea-green -> light-green -> white) driven purely by per-LED BRIGHTNESS.
    => Firmware can store Color0=light-green, Color1=white and crossfade by
       level; the green->white core is a strength effect, not a 3rd color.
  - 50 ms tick: all timing below is quantized to 100 ms (2 ticks).

LOOK IS LOCKED (do NOT change): colors, background, emission strength scale,
glare/halo, view transform. This script only animates per-LED brightness+hue
within the existing palette.
================================================================================
"""

import math
import random

# ------------------------------------------------------------------ PARAMETERS
# Tunable knobs for the motion (exposed for dev). Values below are the BAKED set.
N_DROPS      = 8      # number of drops per 12 s loop  (drop rate = 8 / 12 s)
RIPPLE_SPEED = 5.5    # ring positions traveled per second by the wave front
PULSE_W      = 1.1    # Gaussian sigma (in LED units) — thickness of the front
DECAY_RATE   = 0.65   # exponential amplitude decay per second as it spreads
RIPPLE_LIFE  = 5.5    # seconds a drop stays alive before it's ignored (cutoff)
FLOOR        = 0.07   # base glow floor (0..1) — ring never goes fully dark
SEED         = 42     # RNG seed for drop placement (deterministic)

NUM_LEDS   = 20
LOOP_FRAMES = 720
FPS        = 60
STEP       = 6                       # keyframe every 6 frames (100 ms)
LOOP_S     = LOOP_FRAMES / FPS       # 12.0 s

# Look constants pulled from the scene (DO NOT edit — must match the .blend):
EMISSION_BOOST = 1.5    # scene['arlo_global_emission_boost']
GREEN_BOOST    = 0.4    # scene['arlo_green_boost_amount']
BASE_PEAK      = 730.0  # peak strength before global boost
SP             = BASE_PEAK * EMISSION_BOOST       # 1095.0 peak emission strength
WHITE_START    = 0.45   # raw level at which hue ramp hits light-green -> white

# Palette (sRGB 0..255), locked:
SEA_SRGB   = (60, 179, 113)    # sea-green (adds character at low levels)
LIGHT_SRGB = (120, 215, 80)    # lime/light-green (dominant mid)
# WHITE is (1,1,1) linear at the hot core.


# ----------------------------------------------------------- COLOR / LUMINANCE
def srgb_to_linear(c):
    """sRGB [0..1] -> linear. Required because the scene view transform is Standard."""
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def luminance(rgb):
    """Rec.709 relative luminance of a linear RGB triple."""
    return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]

# Precompute the linear palette anchors exactly as baked:
_SEA   = [srgb_to_linear(c / 255) for c in SEA_SRGB]
_LIGHT = [srgb_to_linear(c / 255) for c in LIGHT_SRGB]
# Green-boost shaping applied to the light anchor (matches scene bake):
_LIGHT = [min(1.0, _LIGHT[0] * 1.2),
          min(1.0, _LIGHT[1] * (1 + GREEN_BOOST)),
          _LIGHT[2]]
_WHITE = [1.0, 1.0, 1.0]
_LIME_LUM = luminance(_LIGHT)

def colcurve(raw):
    """
    Map normalized brightness raw[0..1] -> linear RGB hue.
      raw < WHITE_START : sea-green -> light-green
      raw >= WHITE_START: light-green -> white (hot core)
    """
    raw = max(0.0, min(1.0, raw))
    if raw < WHITE_START:
        t = raw / WHITE_START
        c = [_SEA[k] + (_LIGHT[k] - _SEA[k]) * t for k in range(3)]
    else:
        t = (raw - WHITE_START) / (1.0 - WHITE_START)
        c = [_LIGHT[k] + (_WHITE[k] - _LIGHT[k]) * t for k in range(3)]
    return [min(1.0, x) for x in c]


# ----------------------------------------------------------------- RIPPLE MATH
def ring_distance(a, b):
    """Shortest distance between two ring positions (wrap-around, 0..8)."""
    d = abs(a - b) % NUM_LEDS
    return min(d, NUM_LEDS - d)

def make_drops(seed=SEED):
    """
    Deterministic drop list: (t_land_seconds, center_position_float).
    NOTE: drops are generated with the SAME RNG sequence used at bake time,
    so re-running with seed=42 reproduces the live scene exactly.
    """
    rng = random.Random(seed)
    return [(rng.uniform(0.0, LOOP_S), rng.uniform(0.0, NUM_LEDS))
            for _ in range(N_DROPS)]

def drop_brightness(led_i, t_s, drops):
    """
    Raw (un-normalized) brightness at LED ring-index led_i, time t_s seconds.
    Sum of all live drops: an expanding Gaussian front, decaying over time.
    Seam handling: each drop is evaluated at phase offsets {0, -LOOP_S, +LOOP_S}
    so ripples that start near the loop end bleed seamlessly into the next loop.
    """
    total = 0.0
    for (t_land, center) in drops:
        for offset in (0.0, -LOOP_S, LOOP_S):
            elapsed = t_s - (t_land + offset)
            if elapsed < 0.0 or elapsed > RIPPLE_LIFE:
                continue
            front = RIPPLE_SPEED * elapsed                 # current radius
            d     = ring_distance(led_i, center)
            pulse = math.exp(-0.5 * ((d - front) / PULSE_W) ** 2)
            decay = math.exp(-DECAY_RATE * elapsed)
            total += pulse * decay
    return total

def normalization_max(drops):
    """
    Peak raw brightness over the full LED x sampled-frame grid, used to
    normalize raw -> [0..1]. Baked scene value with seed=42 was 1.527.
    """
    frames = range(1, LOOP_FRAMES + 1, STEP)
    mx = 0.0
    for f in frames:
        t = (f - 1) / FPS
        for i in range(NUM_LEDS):
            v = drop_brightness(i, t, drops)
            if v > mx:
                mx = v
    return mx

def led_state(led_i, t_s, drops, norm_max):
    """
    Final per-LED output at time t_s:
      returns (strength, (r,g,b) linear) ready to write to the Emission node.
    Pipeline: raw -> normalize -> floor-lift -> strength*boost
              -> hue from colcurve -> luminance compensation on strength.
    """
    raw    = drop_brightness(led_i, t_s, drops) / norm_max
    mapped = FLOOR + (1.0 - FLOOR) * raw         # never below the floor glow
    strength = mapped * SP
    col = colcurve(raw)
    # Blue/green read very differently; lift strength on greener (low) phases
    # so character holds without re-tinting. Clamped 1.0..1.4 as baked.
    comp = max(1.0, min(1.4, _LIME_LUM / max(luminance(col), 1e-3)))
    strength *= comp
    return strength, col


# ============================================================== BLENDER BAKE ==
# Run this section inside Blender (bpy available) to (re)create the 32 live
# actions exactly as currently in the scene. Pure section above has NO bpy deps.
def bake_into_blender():
    import bpy

    IBEZ = 2   # fcurve interpolation enum: BEZIER
    HAC  = 4   # handle type enum: AUTO_CLAMPED  (NOTE: foreach_set wants the INT)

    drops    = make_drops(SEED)
    norm_max = normalization_max(drops)     # 1.527 with seed=42
    frames   = list(range(1, LOOP_FRAMES + 1, STEP))   # 120 keys

    # 32 driven meshes: objects "LED<n>_<s>.001", material on slot 0.
    led_objs = [o for o in bpy.data.objects
                if o.name.startswith('LED') and o.name.endswith('.001')
                and o.type == 'MESH']
    def led_index(o):                       # "LED7_2.001" -> 7
        return int(o.name[:-4][3:].split('_')[0])

    built = 0
    for obj in sorted(led_objs, key=lambda o: (led_index(o), o.name)):
        mat = obj.material_slots[0].material
        nt  = mat.node_tree
        i0  = led_index(obj) - 1            # ring index 0..15

        name = f'STYLE_RaindropRipple_{mat.name}'
        if name in bpy.data.actions:
            bpy.data.actions.remove(bpy.data.actions[name])

        # Blender 5.1 layered action (no legacy .fcurves):
        act   = bpy.data.actions.new(name)
        slot  = act.slots.new(id_type='NODETREE', name='Shader Nodetree')
        layer = act.layers.new('Layer')
        strip = layer.strips.new(type='KEYFRAME')
        cbag  = strip.channelbag(slot, ensure=True)

        fs   = cbag.fcurves.new('nodes["Emission"].inputs[1].default_value', index=0)
        fcol = [cbag.fcurves.new('nodes["Emission"].inputs[0].default_value', index=k)
                for k in range(4)]

        n = len(frames)
        sflat = []                          # flat [frame, val, frame, val, ...]
        cflat = [[], [], [], []]
        for f in frames:
            t = (f - 1) / FPS
            strength, col = led_state(i0, t, drops, norm_max)
            sflat += [float(f), strength]
            rgba = col + [1.0]
            for k in range(4):
                cflat[k] += [float(f), rgba[k]]

        # Bulk insert (~100x faster than keyframe_insert):
        fs.keyframe_points.add(n)
        fs.keyframe_points.foreach_set('co', sflat)
        fs.keyframe_points.foreach_set('interpolation', [IBEZ] * n)
        fs.keyframe_points.foreach_set('handle_left_type',  [HAC] * n)
        fs.keyframe_points.foreach_set('handle_right_type', [HAC] * n)
        fs.update()
        for k in range(4):
            fcol[k].keyframe_points.add(n)
            fcol[k].keyframe_points.foreach_set('co', cflat[k])
            fcol[k].keyframe_points.foreach_set('interpolation', [IBEZ] * n)
            fcol[k].keyframe_points.foreach_set('handle_left_type',  [HAC] * n)
            fcol[k].keyframe_points.foreach_set('handle_right_type', [HAC] * n)
            fcol[k].update()

        # Assign live (overrides static default; OB_* actions stay intact):
        if nt.animation_data is None:
            nt.animation_data_create()
        nt.animation_data.action      = act
        nt.animation_data.action_slot = slot
        built += 1

    return {'built': built, 'keys_per_mat': len(frames), 'norm_max': norm_max}


if __name__ == '__main__':
    # Headless sanity check (no Blender): print the brightness field per frame.
    drops = make_drops(SEED)
    nmax  = normalization_max(drops)
    print(f'norm_max = {nmax:.3f}  (baked: 1.527)')
    for f in (1, 31, 205, 481, 601):
        t = (f - 1) / FPS
        vals = [drop_brightness(i, t, drops) / nmax for i in range(NUM_LEDS)]
        bar  = ''.join('#' if v > 0.6 else '+' if v > 0.3 else '.' for v in vals)
        print(f'f{f:3d} t={t:4.1f}s  min={min(vals):.2f} max={max(vals):.2f}  {bar}')
