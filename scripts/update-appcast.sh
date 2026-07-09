#!/usr/bin/env bash
#
# Add a new <item> to docs/appcast.xml for a freshly-built, notarized DMG, and
# sign it with Sparkle's EdDSA key (read from the Keychain — see
# docs/RELEASING.md for how the key pair was created).
#
# Usage:
#   ./scripts/update-appcast.sh <dmg-path> <marketing-version> <build-number> \
#     <release-notes-url> [min-system-version]
#
# Example:
#   ./scripts/update-appcast.sh build/TokenGrass.dmg 1.2.0 15 \
#     https://github.com/shw1606/token-grass/releases/tag/v1.2.0 14.0
#
# Requires Sparkle's `sign_update` CLI tool (download the Sparkle release
# .tar.xz from https://github.com/sparkle-project/Sparkle/releases and use
# bin/sign_update — it's a signing utility, not something the app depends on
# at runtime, so it isn't vendored in this repo).

set -euo pipefail
cd "$(dirname "$0")/.."

DMG_PATH="${1:?dmg path required}"
VERSION="${2:?marketing version required}"
BUILD="${3:?build number required}"
NOTES_URL="${4:?release notes URL required}"
MIN_OS="${5:-14.0}"

SIGN_UPDATE="${SIGN_UPDATE:-$(command -v sign_update || true)}"
if [ -z "$SIGN_UPDATE" ]; then
  echo "sign_update not found. Set SIGN_UPDATE=/path/to/sign_update or add it to PATH." >&2
  exit 1
fi

echo "Signing $DMG_PATH..."
SIG_OUTPUT=$("$SIGN_UPDATE" "$DMG_PATH")
echo "  $SIG_OUTPUT"
ED_SIG=$(echo "$SIG_OUTPUT" | grep -oE 'sparkle:edSignature="[^"]+"' | cut -d'"' -f2)
LENGTH=$(echo "$SIG_OUTPUT" | grep -oE 'length="[^"]+"' | cut -d'"' -f2)

if [ -z "$ED_SIG" ] || [ -z "$LENGTH" ]; then
  echo "Could not parse signature/length from sign_update output" >&2
  exit 1
fi

PUB_DATE=$(date -u "+%a, %d %b %Y %H:%M:%S +0000")
DOWNLOAD_URL="https://github.com/shw1606/token-grass/releases/download/v${VERSION}/TokenGrass.dmg"
APPCAST="docs/appcast.xml"

NEW_ITEM=$(cat <<ITEM
    <item>
      <title>Version ${VERSION}</title>
      <sparkle:releaseNotesLink>${NOTES_URL}</sparkle:releaseNotesLink>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:minimumSystemVersion>${MIN_OS}</sparkle:minimumSystemVersion>
      <enclosure
        url="${DOWNLOAD_URL}"
        sparkle:version="${BUILD}"
        sparkle:shortVersionString="${VERSION}"
        length="${LENGTH}"
        type="application/octet-stream"
        sparkle:edSignature="${ED_SIG}" />
    </item>
ITEM
)

if [ ! -f "$APPCAST" ]; then
  echo "$APPCAST not found - run this after the first appcast.xml is created." >&2
  exit 1
fi

python3 - "$APPCAST" "$NEW_ITEM" <<'PY'
import sys
path, new_item = sys.argv[1], sys.argv[2]
with open(path) as f:
    content = f.read()
marker = "<!-- ITEMS -->"
if marker not in content:
    print(f"marker {marker!r} not found in {path}", file=sys.stderr)
    sys.exit(1)
content = content.replace(marker, new_item + "\n" + marker)
with open(path, "w") as f:
    f.write(content)
PY

echo "Added Version ${VERSION} (build ${BUILD}) to $APPCAST"
echo "Next: git add $APPCAST && git commit, then push (GitHub Pages redeploys automatically)."
