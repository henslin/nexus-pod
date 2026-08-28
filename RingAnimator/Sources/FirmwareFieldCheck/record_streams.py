"""Record each pattern's literal command stream, then replay it to per-LED state."""
import sys, types, json, math, os

P = "/Users/chris/Library/Mobile Documents/com~apple~CloudDocs/Claude/patterns"

events = []   # (t_ms, kind, payload)

def _ev(t, kind, payload): events.append((int(t), kind, payload))

core = types.ModuleType("led_ring_core")
core.TOTAL_LEDS = 16
def set_color0(system, r, g, b, *a): _ev(_now[0], "c0", (r, g, b))
def set_color1(system, r, g, b, *a): _ev(_now[0], "c1", (r, g, b))
def set_fade_rate(system, idx): _ev(_now[0], "fade", idx)
def select_led(system, idx, sel, bits, *a): _ev(_now[0], "led", (idx, bool(sel), bits))
def select_all_leds(system, sel, bits): _ev(_now[0], "all", (bool(sel), bits))
def global_off(system): _ev(_now[0], "off", None)
def schedule_steps(controller, system, steps): return 0
_now = [0]
for n, f in [("set_color0",set_color0),("set_color1",set_color1),("set_fade_rate",set_fade_rate),
             ("select_led",select_led),("select_all_leds",select_all_leds),("global_off",global_off),
             ("schedule_steps",schedule_steps)]:
    setattr(core, n, f)
core.set_driver_color0 = set_color0
core.set_driver_color1 = set_color1
sys.modules["led_ring_core"] = core

ktd = types.ModuleType("ktd2064_ring_model")
class RingLed:
    def __init__(self, *a, **k): self.a = a; self.k = k
class RingStep:
    def __init__(self, *a, **k): self.a = a; self.k = k
ktd.RingLed = RingLed; ktd.RingStep = RingStep
ktd.AGW_RINGLED_TRANSITION_IMMEDIATE = 0
sys.modules["ktd2064_ring_model"] = ktd

class Controller:
    def add_event_at_time_ms(self, t, fn, system, *args, **kw):
        _now[0] = t
        fn(system, *args, **kw)

common = types.ModuleType("pattern_common")
common.__dict__["__file__"] = os.path.join(P, "pattern_common.py")
sys.path.insert(0, "/Users/chris/Desktop")
exec(compile(open(os.path.join(P,"pattern_common.py"),encoding="utf-8").read(),
             "pattern_common.py","exec"), common.__dict__)
sys.modules["pattern_common"] = common

pkg = types.ModuleType("patterns")
pkg.__path__ = [P]
sys.modules["patterns"] = pkg

def replay(evs, total_ms, tick_ms, leds=16):
    """Per-LED (register, selected) state sampled on a grid."""
    evs = sorted(evs, key=lambda e: e[0])
    frames = []
    c0 = (0,0,0); c1 = (0,0,0)
    bits = [0x00]*leds; sel = [False]*leds
    k = 0
    t = 0
    while t <= total_ms:
        while k < len(evs) and evs[k][0] <= t:
            _, kind, pay = evs[k]; k += 1
            if kind == "c0": c0 = pay
            elif kind == "c1": c1 = pay
            elif kind == "led":
                i, s, b = pay; bits[i] = b; sel[i] = s
            elif kind == "all":
                s, b = pay
                for i in range(leds): bits[i] = b; sel[i] = s
            elif kind == "off":
                for i in range(leds): bits[i] = 0x00; sel[i] = False
        frames.append({"t": t, "c0": list(c0), "c1": list(c1),
                       "bits": list(bits), "sel": [1 if x else 0 for x in sel]})
        t += tick_ms
    return frames

out = {}
for fn in sorted(os.listdir(P)):
    if not fn.endswith(".py"): continue
    name = fn[:-3]
    if name in ("pattern_common","led_ring_patterns","__init__"): continue
    src = open(os.path.join(P,fn),encoding="utf-8").read()
    if "def schedule_" not in src: continue
    mod = types.ModuleType(name); mod.__dict__.update(common.__dict__)
    mod.__dict__["__name__"] = name
    mod.__dict__["__file__"] = os.path.join(P, fn)
    sys.modules["patterns." + name] = mod
    try:
        exec(compile(src, fn, "exec"), mod.__dict__)
        sched = mod.__dict__.get("schedule_" + name)
        if sched is None: continue
        events.clear(); _now[0] = 0
        total = sched(Controller(), None)
        total = int(total) if total else 8000
        tick = 100
        frames = replay(list(events), min(total, 24000), tick)
        out[name] = {"total_ms": total, "tick_ms": tick,
                     "events": len(events), "frames": frames,
                     "raw": [[t, k, list(pay) if isinstance(pay, tuple) else pay]
                             for (t, k, pay) in sorted(events, key=lambda e: e[0])]}
        print(f"  {name}: {len(events)} events, {total} ms")
    except Exception as e:
        print(f"  SKIP {name}: {type(e).__name__}: {e}")

json.dump(out, open(sys.argv[1],"w"))
print(f"\nrecorded {len(out)} patterns")
