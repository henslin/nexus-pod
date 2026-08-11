#!/bin/bash
# Builds, signs, notarizes, staples, and zips RingAnimator for sharing with
# the team. Run this from anywhere — it cd's into place itself.
#
# One-time setup this script assumes is already done:
#   - Signed into Xcode with an Apple ID enrolled in the Developer Program
#   - A "Developer ID Application" certificate exists in Keychain
#   - `xcrun notarytool store-credentials "notarytool-profile" ...` has been run
#
# Usage:
#   chmod +x release.sh   (only needed once)
#   ./release.sh

set -e

# `swift build` on the command line defaults to the bare Command Line Tools
# SDK, which doesn't carry the SwiftUI macro plugins (@State, @Binding, etc.)
# that ship with the full Xcode app — that mismatch is what caused the
# "external macro implementation ... could not be found" build failure.
# Point DEVELOPER_DIR at whatever Xcode app is actually installed (handles
# "Xcode.app", "Xcode-beta.app", etc.) without touching xcode-select globally.
XCODE_APP=$(ls -d /Applications/Xcode*.app 2>/dev/null | head -n 1)
if [ -n "$XCODE_APP" ]; then
  export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
  echo "==> Using toolchain: $DEVELOPER_DIR"
else
  echo "Could not find an Xcode app in /Applications — aborting." >&2
  exit 1
fi

PROJECT_DIR="/Users/chris/Library/Mobile Documents/com~apple~CloudDocs/Claude/Nexus Ring App"
APP_NAME="RingAnimator"
TEAM_ID="NR8MAUF922"
SIGN_IDENTITY="Developer ID Application: Chris Henslin ($TEAM_ID)"
NOTARY_PROFILE="notarytool-profile"
BUILD_DIR="/tmp/${APP_NAME}Release"

echo "==> Building release binary..."
cd "$PROJECT_DIR/RingAnimator"
swift build -c release --product "$APP_NAME"

echo "==> Assembling app bundle..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/$APP_NAME.app/Contents/MacOS"
mkdir -p "$BUILD_DIR/$APP_NAME.app/Contents/Resources"
cp "$PROJECT_DIR/$APP_NAME.app/Contents/Info.plist" "$BUILD_DIR/$APP_NAME.app/Contents/Info.plist"
cp ".build/release/$APP_NAME" "$BUILD_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"
chmod +x "$BUILD_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"

cd "$BUILD_DIR"
xattr -cr "$APP_NAME.app"

echo "==> Signing with hardened runtime..."
codesign --deep --force --options runtime --sign "$SIGN_IDENTITY" "$APP_NAME.app"

echo "==> Submitting for notarization (usually 1-15 minutes)..."
ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME-notarize.zip"
xcrun notarytool submit "$APP_NAME-notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$APP_NAME.app"

echo "==> Packaging final zip..."
ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME-macOS-notarized.zip"
cp "$APP_NAME-macOS-notarized.zip" "$PROJECT_DIR/"

echo ""
echo "Done — $APP_NAME-macOS-notarized.zip is ready to share, in your project folder."
