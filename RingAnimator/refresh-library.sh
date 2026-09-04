#!/usr/bin/env bash
#
# Cuts a new bundled use-case library from this machine's own animations.
#
#   ./refresh-library.sh
#
# This is the producer side of `UseCaseLibrary`: whoever is curating the
# animations edits them in the app, runs this, and commits. The next build
# ships them, and on everyone else's machine the launch sync adds what's
# new and updates what they haven't edited — see UseCaseLibrary.sync.
#
# The timestamp it stamps in is what the Use Cases column shows, so run
# this when the library is actually ready rather than as a habit: a date
# that moves on every build tells nobody anything.

set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SOURCE="${1:-$HOME/Library/Application Support/RingAnimator/use-cases.json}"
DEST="Sources/RingAnimatorCore/Resources/use-case-library.json"

if [ ! -f "$SOURCE" ]; then
    printf '\033[31mNo animations at %s\033[0m\n' "$SOURCE"
    exit 1
fi

python3 - "$SOURCE" "$DEST" <<'PY'
import json, sys, datetime

source, dest = sys.argv[1], sys.argv[2]
presets = json.load(open(source))

try:
    previous = json.load(open(dest))
    was = len(previous["presets"])
    cut = previous["generatedAt"]
except Exception:
    was, cut = 0, "never"

stamp = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)
json.dump(
    {"generatedAt": stamp.isoformat().replace("+00:00", "Z"), "presets": presets},
    open(dest, "w"),
    indent=2,
    sort_keys=True,
)
print(f"  was {was} animations, cut {cut}")
print(f"  now {len(presets)} animations, cut {stamp.isoformat()}")
PY

printf '\n\033[32mBundled library refreshed.\033[0m Run ./preflight.sh, then commit %s\n' "$DEST"
