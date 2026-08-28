#!/usr/bin/env bash
#
# Everything that must pass before cutting a release.
#
# This exists as a script rather than a list in CLAUDE.md because the list
# was wrong the moment it was written: a plain `swift run FirmwareFieldCheck`
# in this repo fails with "resource fork, Finder information, or similar
# detritus not allowed". SwiftPM codesigns the resource bundle during the
# build, iCloud re-stamps com.apple.FinderInfo mid-flight, and the build
# dies — so *every* build here needs a scratch path outside iCloud, not just
# the release one. A checklist you have to remember to decorate is a
# checklist that gets run wrong.
#
#   ./preflight.sh
#
# Override the pattern library location with PATTERNS_DIR.

set -uo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SCRATCH="${NEXUS_BUILD_DIR:-$HOME/Developer/NexusPod-Build}"
PATTERNS_DIR="${PATTERNS_DIR:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/Claude/patterns}"

failed=0
step() {
    printf '\n\033[1m→ %s\033[0m\n' "$1"
}
result() {
    if [ "$1" -eq 0 ]; then
        printf '  \033[32m✓ %s\033[0m\n' "$2"
    else
        printf '  \033[31m✗ %s\033[0m\n' "$2"
        failed=1
    fi
}

step "Firmware fidelity — ported fields and recorded streams"
swift run --scratch-path "$SCRATCH" FirmwareFieldCheck 2>&1 | tail -3
result "${PIPESTATUS[0]}" "FirmwareFieldCheck"

step "Generated exports still compile"
swift run --scratch-path "$SCRATCH" ExportCheck 2>&1 | tail -2
result "${PIPESTATUS[0]}" "ExportCheck"

step "Pattern library matches the committed fixtures"
if [ -d "$PATTERNS_DIR" ]; then
    python3 Sources/FirmwareFieldCheck/library_manifest.py verify "$PATTERNS_DIR"
    result $? "library manifest"
else
    printf '  \033[33m! skipped — no pattern library at %s\033[0m\n' "$PATTERNS_DIR"
    printf '    (set PATTERNS_DIR; recordings cannot be confirmed current without it)\n'
fi

step "iOS target builds"
xcodebuild -project ../RingAnimatoriOS/RingAnimatoriOS.xcodeproj \
    -target RingAnimatoriOS -sdk iphonesimulator -configuration Debug \
    SYMROOT="$SCRATCH/ios" build >/dev/null 2>&1
result $? "RingAnimatoriOS"

printf '\n'
if [ "$failed" -eq 0 ]; then
    printf '\033[32mReady to release.\033[0m Bump Packaging/Info.plist, then Packaging/build_and_sign.sh\n'
else
    printf '\033[31mNot ready.\033[0m Fix the failures above before releasing.\n'
fi
exit "$failed"
