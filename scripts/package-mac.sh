#!/usr/bin/env bash
#
# Build, sign, and package the macOS companion into a distributable DMG.
#
# Works today for a local / ad-hoc DMG (unsigned). For a public release, set the
# signing + notarization env vars below — everything is gated so the script
# degrades gracefully until you have a paid Apple Developer account.
#
# Usage:
#   ./scripts/package-mac.sh                 # ad-hoc DMG (local testing)
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE="tokengrass" \
#     ./scripts/package-mac.sh               # signed + notarized + stapled
#
# NOTARY_PROFILE is a notarytool keychain profile created once with:
#   xcrun notarytool store-credentials tokengrass \
#     --apple-id you@example.com --team-id TEAMID --password <app-specific-pw>

set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="TokenGrass"
SCHEME="TokenGrassMac"
DERIVED="$(mktemp -d)"
OUT="build"
DMG="$OUT/${APP_NAME}.dmg"
STAGE="$(mktemp -d)"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

echo "▸ Generating project…"
xcodegen generate >/dev/null

echo "▸ Building Release…"
xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "$SCHEME" \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build >/dev/null

APP="$DERIVED/Build/Products/Release/${APP_NAME}.app"
[ -d "$APP" ] || { echo "✗ build product not found at $APP"; exit 1; }

mkdir -p "$OUT"
cp -R "$APP" "$STAGE/${APP_NAME}.app"
APP="$STAGE/${APP_NAME}.app"

if [ -n "${DEVELOPER_ID:-}" ]; then
  echo "▸ Signing with Developer ID (hardened runtime)…"
  codesign --force --deep --options runtime --timestamp \
    --sign "$DEVELOPER_ID" "$APP"
else
  echo "▸ Ad-hoc signing (no Developer ID set — not for public release)…"
  codesign --force --deep --sign - "$APP"
fi

echo "▸ Building DMG…"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

if [ -n "${DEVELOPER_ID:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "▸ Notarizing (this can take a few minutes)…"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "▸ Stapling…"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
else
  echo "▸ Skipping notarization (set DEVELOPER_ID + NOTARY_PROFILE to enable)."
fi

echo "✓ $DMG"
