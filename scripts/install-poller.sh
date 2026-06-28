#!/usr/bin/env bash
#
# Install the TokenGrass background poller as a macOS LaunchAgent.
#   - builds a release binary, copies it to a stable path, ad-hoc signs it
#   - runs it once interactively so you can grant Keychain access
#   - installs + loads a LaunchAgent that polls every N seconds (+ on wake)
#
# Usage:   ./scripts/install-poller.sh [interval_seconds]   (default 10800 = 3h)
# Remove:  ./scripts/uninstall-poller.sh

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$REPO/TokenGrassCore"
BIN_DIR="$HOME/.tokengrass/bin"
BIN="$BIN_DIR/tokengrass-poll"
LOG="$HOME/.tokengrass/poll.log"
LABEL="dev.yulebuilds.tokengrass.poll"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
INTERVAL="${1:-10800}"

echo "▸ release 바이너리 빌드…"
( cd "$PKG" && swift build -c release --product tokengrass-poll )

mkdir -p "$BIN_DIR"
cp -f "$PKG/.build/release/tokengrass-poll" "$BIN"
# Ad-hoc sign so the Keychain ACL ("항상 허용") sticks to a stable identity.
codesign --force --sign - "$BIN" 2>/dev/null || true
echo "▸ 바이너리 설치: $BIN"

echo "▸ LaunchAgent 작성: $PLIST  (간격 ${INTERVAL}s)"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$LABEL</string>
	<key>ProgramArguments</key><array><string>$BIN</string></array>
	<key>StartInterval</key><integer>$INTERVAL</integer>
	<key>RunAtLoad</key><true/>
	<key>ProcessType</key><string>Background</string>
	<key>StandardOutPath</key><string>$LOG</string>
	<key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PLISTEOF
plutil -lint "$PLIST" >/dev/null

echo
echo "▸ 먼저 Keychain 권한을 1회 부여합니다 (대화형 실행)."
echo "  팝업이 뜨면 반드시 [항상 허용 / Always Allow] 를 누르세요 — 그래야 백그라운드에서도 토큰을 읽습니다."
echo "  ---------------------------------------------------------------"
"$BIN" || true
echo "  ---------------------------------------------------------------"

echo "▸ LaunchAgent 로드…"
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo
echo "✓ 설치 완료. ${INTERVAL}s마다 + 잠에서 깰 때 자동 폴링."
echo "  로그:   tail -f $LOG"
echo "  상태:   ~/.tokengrass/poll-state.json"
echo "  제거:   $REPO/scripts/uninstall-poller.sh"
