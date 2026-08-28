"""Record (or verify) exactly which pattern-library snapshot the fixtures came from.

The app does not own `patterns/` and shouldn't: that folder is an extract of
a firmware repo — it imports `led_ring_core` and `ktd2064_ring_model`, which
live upstream next to the C. Vendoring a copy here would fork the source of
truth for the device's behavior, which is worse than depending on it.

What the app does own is *provenance*. `firmware-streams.json` and the two
check fixtures are generated from a specific state of that library, and
without a record of which state, "are our recordings stale?" is unanswerable
— you'd have to re-record and diff to find out.

    python3 library_manifest.py write <patterns-dir>    # after re-recording
    python3 library_manifest.py verify <patterns-dir>   # before trusting them

Verify exits non-zero on drift, so it can gate a release.
"""
import hashlib
import os
import sys

MANIFEST = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "pattern-library.manifest")


def digests(folder):
    out = {}
    for name in sorted(os.listdir(folder)):
        if not name.endswith(".py"):
            continue
        with open(os.path.join(folder, name), "rb") as handle:
            out[name] = hashlib.sha256(handle.read()).hexdigest()
    return out


def write(folder):
    entries = digests(folder)
    combined = hashlib.sha256(
        "".join(f"{n}:{h}" for n, h in sorted(entries.items())).encode()
    ).hexdigest()
    with open(MANIFEST, "w") as handle:
        handle.write(f"# pattern library snapshot the committed fixtures were built from\n")
        handle.write(f"# regenerate with: python3 library_manifest.py write <patterns-dir>\n")
        handle.write(f"snapshot {combined}\n")
        for name, h in sorted(entries.items()):
            handle.write(f"{h}  {name}\n")
    print(f"wrote {len(entries)} files, snapshot {combined[:12]}")


def verify(folder):
    if not os.path.exists(MANIFEST):
        print("no manifest — run `write` first")
        return 1
    recorded = {}
    for line in open(MANIFEST):
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("snapshot "):
            continue
        h, name = line.split("  ", 1)
        recorded[name] = h

    current = digests(folder)
    changed = sorted(n for n in recorded.keys() & current.keys() if recorded[n] != current[n])
    removed = sorted(recorded.keys() - current.keys())
    added = sorted(current.keys() - recorded.keys())

    if not (changed or removed or added):
        print(f"✅ pattern library matches the fixtures ({len(current)} files)")
        return 0

    print("❌ pattern library has drifted from the committed fixtures")
    for n in changed:
        print(f"   changed: {n}")
    for n in removed:
        print(f"   removed: {n}")
    for n in added:
        print(f"   added:   {n}")
    print("\nRe-record before releasing:")
    print("   python3 record_streams.py   <streams.json>")
    print("   python3 dump_reference.py   <levels.json>")
    print("   python3 library_manifest.py write <patterns-dir>")
    return 1


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("write", "verify"):
        print(__doc__)
        raise SystemExit(2)
    raise SystemExit(write(sys.argv[2]) if sys.argv[1] == "write" else verify(sys.argv[2]))
