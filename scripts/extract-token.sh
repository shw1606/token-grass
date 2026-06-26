#!/usr/bin/env bash
#
# TokenGrass — Claude Code credential helper.
#
# Prints your Claude Code OAuth credentials as a single line of JSON so you can
# paste it once into the TokenGrass app. Nothing is uploaded anywhere; this only
# reads what's already on your machine.
#
# Usage:   ./scripts/extract-token.sh
#
# NOTE: The exact Keychain service/account names still need on-device
# verification (DESIGN §6/§7). If this doesn't find anything, the most reliable
# path is the long-lived token below.

set -euo pipefail

echo "TokenGrass credential helper" >&2
echo "----------------------------" >&2

# 1) Linux / remote server: plain credentials file.
if [[ -f "$HOME/.claude/.credentials.json" ]]; then
  echo "Found ~/.claude/.credentials.json — copy the line below:" >&2
  tr -d '\n' < "$HOME/.claude/.credentials.json"
  echo
  exit 0
fi

# 2) macOS: Claude Code stores credentials in the login Keychain.
if command -v security >/dev/null 2>&1; then
  if cred=$(security find-generic-password -s "Claude Code" -w 2>/dev/null); then
    echo "Found credentials in the macOS Keychain — copy the line below:" >&2
    printf '%s' "$cred" | tr -d '\n'
    echo
    exit 0
  fi
fi

cat >&2 <<'EOF'

Could not find Claude Code credentials automatically.

Recommended fallback — create a long-lived token (no refresh needed):

    claude setup-token

Then paste the value it prints into TokenGrass. This avoids the OAuth refresh
endpoint entirely (which is Cloudflare-protected and may reject off-CLI calls).
EOF
exit 1
