# Ziris — "Listening" Ripple animation · Blender render handoff

**Animation:** `pattern_listening` — the voice-assistant "listening" LED feedback for Ziris.
Calm electric-blue water with white glimmers rippling around the ring, the way an Alexa
light ring behaves while a user is talking to the device ("Hey Arlo, arm my system"). It is
a re-tuned version of the existing blue/white Raindrop Ripple, tuned to read as *attentive
listening*.

**What you're producing:** a rendered clip of one seamless 12-second loop of this animation.

---

## Files (all in this project)

| File | Role |
|---|---|
| `blender 3D CAD file/Arlo_Ziris.blend` | The scene. Open this in Blender. |
| `blender 3D CAD file/blender_ziris_led_integration_emissive.py` | The script. Contains `pattern_listening()`. |
| `ripple.py` (project root) | Canonical motion math the pattern imports. Must stay in place. |
| `ktd2064_blender_simulator.py`, `ktd2064_pattern_library.py` | Support modules. Do not edit. |

Requirements: a **Cycles-capable Blender** build (GPU strongly recommended). Keep the folder
structure intact — the script finds `ripple.py` one level up from the `blender 3D CAD file/`
folder.

---

## Steps

1. **Open** `blender 3D CAD file/Arlo_Ziris.blend`.
2. Go to the **Scripting** workspace and open `blender_ziris_led_integration_emissive.py`
   in the Text Editor (Text ▸ Open).
3. At the bottom of the file, in `main()`'s pattern list, make sure **only**
   `system, controller = pattern_listening()` is **un-commented** and every other
   `pattern_*()` line is commented out.
4. **Run** the script (Text ▸ Run Script, or Alt+P). It bakes the LED keyframes onto the
   timeline. You'll see a console summary (drop count, `NORM_MAX`, transition count).
5. **Preview:** scrub or press Space in the 3D viewport / timeline to sanity-check the loop
   before committing to a full render.
6. **Render** using one of the built-in entrypoints from the Python console (bottom of the
   Scripting workspace):
   - `batch_render_preview()` — 25% res, fastest, for a quick look.
   - `batch_render_fast()` — 50% res, balanced.
   - `batch_render_final()` — 100% res, 500 samples, for the deliverable.

   > Running the script via `Alt+P` also auto-runs `main()` then `batch_render_fast()` (see
   > the `if __name__ == "__main__"` block). For the final deliverable, run
   > `batch_render_final()` manually instead.

7. **Output location & format:** check Blender's **Output Properties** tab for the frame
   output folder and file format before the final render. Confirm the frame range covers the
   full loop (fps × 12 s). Deliver either the image sequence or an encoded video of the
   single 12 s loop.

---

## What it should look like (accept/reject checklist)

- Floor is **electric blue** `(40, 120, 255)`, always lit — the ring never goes fully dark.
- Multiple **white spots** ripple outward and fade, scattered around the ring, blinking
  fairly frequently but reading as **crisp points**, not a white wash.
- Fronts spread **symmetrically in both directions** (no spin, no preferred direction).
- Motion is **calm and liquid** — slower and gentler than the busier ambient ripple.
- The **12 s loop wraps seamlessly** — no visible pop or jump at the loop boundary.

If the white-spot density looks off, it's a one-line tweak in `pattern_listening` (see
parameters below) — flag it and it can be re-baked in seconds.

---

## Final parameters (reference — for tweaks/re-bakes only)

These are the baked defaults on `pattern_listening`. You don't need to change anything to
render; this is here so a tweak request is quick.

```
color0_rgb           = (40, 120, 255)   # electric-blue floor  (Color0)
color1_rgb           = (255, 255, 255)  # white glimmer         (Color1)
white_core_threshold = 0.45             # lower = MORE white spots (nudge 0.40–0.50)
n_drops              = 9                 # more drops = more simultaneous white spots
pulse_w              = 0.9              # front thickness; lower = crisper spots
ripple_speed         = 4.0              # slower = more serene
decay_rate           = 0.55            # gentler fade / longer laps
fade_rate_idx        = 4               # global fade tau (liquid crossfade)
loop_seconds         = 12.0            # seamless loop length — do not change
tick_ms              = 100             # selection cadence (2× 50 ms firmware tick)
seed                 = 7               # listening-specific drop table
```

Quick tuning: **too much white** → raise `white_core_threshold` toward 0.50;
**too little** → lower toward 0.40. Any change to `n_drops`/`pulse_w` recomputes `NORM_MAX`
automatically — just re-run the script.

---

## Do-not-touch (hardware accuracy)

This scene is WYSIWYG with real KTD2064 firmware. Please **don't edit**
`ktd2064_blender_simulator.py`, and don't change the baked constants in `ripple.py`
(they define the separate ambient `pattern_ripple` and must stay put). Rendering and
re-baking `pattern_listening` is all that's needed here. If something looks wrong that
seems to require a code change beyond the parameters above, flag it rather than editing the
simulator.
