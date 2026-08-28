import sys, types, json, math, os

P = "/Users/chris/Library/Mobile Documents/com~apple~CloudDocs/Claude/patterns"

# Stub led_ring_core: only TOTAL_LEDS matters for the maths.
core = types.ModuleType("led_ring_core")
core.TOTAL_LEDS = 20
for name in ["set_color0","set_color1","set_fade_rate","select_led","select_all_leds",
             "global_off","set_driver_color0","set_driver_color1","schedule_steps"]:
    setattr(core, name, lambda *a, **k: None)
sys.modules["led_ring_core"] = core

common_src = open(os.path.join(P, "pattern_common.py"), encoding="utf-8").read()
common = types.ModuleType("pattern_common")
common.__dict__["__name__"] = "pattern_common"
exec(compile(common_src, "pattern_common.py", "exec"), common.__dict__)
sys.modules["pattern_common"] = common

captured = {}
def capturing(controller, system, level, c0, c1, fade_rate_idx, loop_seconds,
              threshold=0.5, tick_ms=100):
    captured["level"] = level
    captured["threshold"] = threshold
    captured["tick_ms"] = tick_ms
    captured["loop_seconds"] = loop_seconds
    return int(loop_seconds * 1000)

# Patch on the module object: these files do
# `from pattern_common import _schedule_level_threshold`, which re-reads
# sys.modules at exec time and would otherwise restore the real one.
common._schedule_level_threshold = capturing

out = {}
for fn in sorted(os.listdir(P)):
    if not fn.endswith(".py"): continue
    src = open(os.path.join(P, fn), encoding="utf-8").read()
    if "def schedule_" not in src or "def _schedule" in src: continue
    name = fn[:-3]
    mod = types.ModuleType(name)
    mod.__dict__.update(common.__dict__)
    mod.__dict__["__name__"] = name
    try:
        exec(compile(src, fn, "exec"), mod.__dict__)
        sched = mod.__dict__.get("schedule_" + name)
        if sched is None: continue
        captured.clear()
        sched(None, None)
        lvl = captured.get("level")
        if lvl is None: continue
        grid = []
        for i in range(20):
            for step in range(40):
                t = step * 0.25
                grid.append(float(lvl(i, t)))
        params = {}
        if lvl.__closure__:
            for var, cell in zip(lvl.__code__.co_freevars, lvl.__closure__):
                try:
                    v = cell.cell_contents
                    if isinstance(v, (int, float, str)): params[var] = v
                except ValueError:
                    pass
        out[name] = {"params": params,
                     "threshold": captured["threshold"],
                     "tick_ms": captured["tick_ms"],
                     "loop_seconds": captured["loop_seconds"],
                     "grid": grid}
        print(f"  {name}\n      threshold={captured['threshold']} tick={captured['tick_ms']} loop={captured['loop_seconds']}s params={params}")
    except Exception as e:
        print(f"  SKIP {name}: {type(e).__name__}: {e}")

json.dump(out, open(sys.argv[1], "w"))
print(f"\ncaptured {len(out)} level fields")
