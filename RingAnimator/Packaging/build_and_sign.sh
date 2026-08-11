#!/bin/bash
# Builds RingAnimator (the Mac design tool) in Release, assembles it into a
# real RingAnimator.app bundle with the icon + Info.plist in this folder,
# code-signs it with your Developer ID, notarizes it with Apple, and staples
# the notarization ticket — the end result is a .app that opens with a
# plain double-click, no Gatekeeper "unidentified developer" warning, no
# right-click-Open workaround needed for whoever you send it to.
#
# Run this from a Terminal on your own Mac, from inside the RingAnimator
# package folder (the one with Package.swift in it):
#   cd path/to/RingAnimator
#   chmod +x Packaging/build_and_sign.sh   # first time only
#   Packaging/build_and_sign.sh
#
# ── One-time setup before your first run ──────────────────────────────
#
# 1. SIGNING_IDENTITY below — find your exact Developer ID Application
#    identity string:
#      security find-identity -v -p codesigning
#    Copy the quoted name exactly (e.g. "Developer ID Application: Chris
#    Henslin (NR8MAUF922)") into SIGNING_IDENTITY below.
#
# 2. Notarization credentials — Apple's notarytool needs an app-specific
#    password (not your normal Apple ID password). Generate one at
#    appleid.apple.com → Sign-In and Security → App-Specific Passwords,
#    then store it once, locally, so you never have to paste it again:
#      xcrun notarytool store-credentials "ringanimator-notary" \
#        --apple-id "your-apple-id@example.com" \
#        --team-id "NR8MAUF922" \
#        --password "the-app-specific-password"
#    That saves it to your Mac's Keychain under the profile name
#    "ringanimator-notary", which NOTARY_PROFILE below already assumes.

set -euo pipefail

# ── Fill these in ──────────────────────────────────────────────────────
SIGNING_IDENTITY="Developer ID Application: Chris Henslin (NR8MAUF922)"
NOTARY_PROFILE="ringanimator-notary"
# ────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="RingAnimator"
BUILD_DIR="$PACKAGE_DIR/.build/release"
STAGE_DIR="$PACKAGE_DIR/Packaging/stage"
APP_BUNDLE="$STAGE_DIR/$APP_NAME.app"

echo "→ Building Release..."
cd "$PACKAGE_DIR"
swift build -c release

echo "→ Assembling $APP_NAME.app..."
rm -rf "$STAGE_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$SCRIPT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# SwiftPM generates a resource bundle for RingAnimatorCore's Resources/
# folder (icons, demo App UI screenshots) — its exact name depends on the
# toolchain version, so this copies *any* .bundle found in the build
# output rather than assuming one name. If images go missing at runtime
# (tab icons, demo screenshots), check that a .bundle actually landed in
# Contents/Resources here.
found_bundle=false
for bundle in "$BUILD_DIR"/*.bundle; do
    [ -d "$bundle" ] || continue
    cp -R "$bundle" "$APP_BUNDLE/Contents/Resources/"
    echo "  copied resource bundle: $(basename "$bundle")"
    found_bundle=true
done
if [ "$found_bundle" = false ]; then
    echo "  ⚠️  no .bundle found in $BUILD_DIR — if the app's images don't"
    echo "     load, this is why. Check RingAnimatorCore's Resources/ setup."
fi

echo "→ Code signing (hardened runtime)..."
codesign --deep --force --options runtime \
    --sign "$SIGNING_IDENTITY" \
    "$APP_BUNDLE"

echo "→ Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "→ Zipping for notarization submission..."
NOTARY_ZIP="$STAGE_DIR/$APP_NAME-notarize.zip"
ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARY_ZIP"

echo "→ Submitting to Apple notary service (this can take a few minutes)..."
xcrun notarytool submit "$NOTARY_ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "→ Stapling notarization ticket to the app..."
xcrun stapler staple "$APP_BUNDLE"

echo "→ Building final distributable zip..."
FINAL_ZIP="$PACKAGE_DIR/$APP_NAME.zip"
rm -f "$FINAL_ZIP"
ditto -c -k --keepParent "$APP_BUNDLE" "$FINAL_ZIP"

echo ""
echo "✅ Done: $FINAL_ZIP"
echo "   That zip is what you share — unzip it, drag RingAnimator.app"
echo "   anywhere, double-click to open. No Gatekeeper prompt."
