#!/usr/bin/env bash
#
# Zip the pattern library to ship alongside the app.
#
# The app embeds *recordings* of these patterns, not the patterns
# themselves, so a recipient who wants to change one — or check what the app
# is claiming the device does — needs the source. This packages it.
#
# It refuses to build a zip whose contents don't match the manifest the
# committed fixtures were generated from. Shipping a library that disagrees
# with the app's recordings is worse than shipping no library: the app would
# be describing an animation the source no longer produces, and the zip
# would look like proof.
#
#   Packaging/package_patterns.sh [patterns-dir]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(dirname "$SCRIPT_DIR")"
PATTERNS_DIR="${1:-${PATTERNS_DIR:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/Claude/patterns}}"
MANIFEST="$PACKAGE_DIR/Sources/FirmwareFieldCheck/pattern-library.manifest"

[ -d "$PATTERNS_DIR" ] || { echo "no pattern library at $PATTERNS_DIR"; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SCRIPT_DIR/Info.plist")"
OUT="$PACKAGE_DIR/Nexus Pod patterns $VERSION.zip"

echo "→ Verifying the library matches the app's recordings..."
python3 "$PACKAGE_DIR/Sources/FirmwareFieldCheck/library_manifest.py" verify "$PATTERNS_DIR"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
DEST="$STAGE/patterns"
mkdir -p "$DEST"

echo "→ Collecting sources..."
cp "$PATTERNS_DIR"/*.py "$DEST/"
# Design handoff notes travel with the pattern they document.
for extra in "$PATTERNS_DIR"/*.md; do
    [ -e "$extra" ] && cp "$extra" "$DEST/"
done
cp "$MANIFEST" "$DEST/pattern-library.manifest"

SNAPSHOT="$(awk '/^snapshot /{print $2}' "$MANIFEST")"

cat > "$DEST/README.md" <<EOF
# Nexus Pod — LED ring pattern library

The pattern sources behind Nexus Pod $VERSION.

The app does not run these files. It ships *recordings* of them: every
pattern's scheduler was run once against a recorder that captured each
\`set_color\` / \`select_led\` command with its timestamp, and the app replays
that. So what you see in the app is the device's literal output, and this
folder is where that output comes from.

**Snapshot:** \`$SNAPSHOT\`

\`pattern-library.manifest\` is a sha256 per file plus that combined id. The
app's committed fixtures were generated from exactly this state; if the two
ever disagree, the app's recordings are stale and need regenerating.

## This is an extract, not a runnable package

\`led_ring_core\` and \`ktd2064_ring_model\` are imported but not included —
they live in the firmware repo alongside \`agw_ringled_patterns_harpy.c\`.
These files won't execute standalone. They are here to be read, diffed and
edited, with changes going back to that repo rather than staying here.

## The ring is 20 LEDs

Everything derives from \`TOTAL_LEDS\` rather than assuming a count, so the
library follows the hardware. That matters in three places that used to be
hardcoded to 16: the geometry constants (\`TOP_LEDS\`, the halves,
\`SYMMETRIC_PAIRS\`, \`led_opposite\`, \`led_mirror\`), the counter-rotating
comet starts, and the battery fill levels — which are now
\`TOTAL_LEDS // 4\`, \`// 2\` and \`3 * // 4\`, so \`battery_25\` means 25% of
the ring rather than a fixed four LEDs.
EOF

echo "→ Zipping..."
rm -f "$OUT"
# --norsrc --noextattr, not --sequesterRsrc. Every file here comes out of
# iCloud carrying a com.apple.FinderInfo xattr (the same one that breaks
# codesign — see preflight.sh), and --sequesterRsrc preserves those by
# writing an AppleDouble `__MACOSX/._foo.py` beside every real script. That
# doubled the archive's file count with binary sidecars that end in `.py`,
# which the folder importer then has to know to ignore. Dropping the
# metadata is strictly better: these are plain text files whose resource
# forks carry nothing anyone wants.
(cd "$STAGE" && ditto -c -k --norsrc --noextattr --noqtn patterns "$OUT")

echo
echo "✅ $OUT"
echo "   $(ls "$DEST"/*.py | wc -l | tr -d ' ') sources, snapshot ${SNAPSHOT:0:12}, $(du -h "$OUT" | cut -f1)"
