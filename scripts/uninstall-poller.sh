#!/usr/bin/env bash
# Remove the TokenGrass background poller LaunchAgent.
set -euo pipefail

LABEL="dev.yulebuilds.tokengrass.poll"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
rm -f "$HOME/.tokengrass/bin/tokengrass-poll"

echo "✓ 폴러 제거됨."
echo "  누적 상태/로그는 ~/.tokengrass/ 에 남겨둠 (완전 삭제: rm -rf ~/.tokengrass)"
