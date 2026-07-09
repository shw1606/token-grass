# Releasing

TokenGrass ships as two artifacts: the **macOS companion** (direct download, via
GitHub Releases) and the **iOS app + widget** (App Store / TestFlight). Both the
notarization below and any App Store submission require the **paid Apple Developer
Program** ($99/yr).

## Prerequisites (one-time, after enrollment)

1. **Team ID** — from [developer.apple.com/account](https://developer.apple.com/account)
   → Membership details. Put it in `project.yml` under `DEVELOPMENT_TEAM`, then
   `xcodegen generate`.
2. **Developer ID Application** certificate (for the Mac DMG) — create in Xcode →
   Settings → Accounts → Manage Certificates, or on the developer portal.
3. **notarytool credentials** — store an app-specific password once:
   ```bash
   xcrun notarytool store-credentials tokengrass \
     --apple-id you@example.com --team-id TEAMID --password <app-specific-pw>
   ```

## macOS companion (GitHub Release)

```bash
# Ad-hoc DMG for local testing (works today, no account needed):
./scripts/package-mac.sh

# Signed + notarized + stapled DMG for public download (needs the account):
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="tokengrass" \
  ./scripts/package-mac.sh
```

Then cut the release:

```bash
gh release create v0.1.0 build/TokenGrass.dmg \
  --title "TokenGrass 0.1.0" \
  --notes-file docs/release-notes/v0.1.0.md
```

Bump the Mac target's `MARKETING_VERSION` (and global `CURRENT_PROJECT_VERSION`)
in `project.yml` before tagging. A notarized + stapled DMG opens on any Mac
without a Gatekeeper warning.

### Auto-updates (Sparkle)

The Mac companion checks `docs/appcast.xml` (served via GitHub Pages at
`https://shw1606.github.io/token-grass/appcast.xml`) and can update itself in
place. After notarizing a new DMG and creating its GitHub Release:

```bash
# One-time: download Sparkle's CLI tools (not vendored — they're release-signing
# utilities, not a runtime dependency). Get sign_update from:
#   https://github.com/sparkle-project/Sparkle/releases → Sparkle-X.Y.Z.tar.xz → bin/sign_update
# The private EdDSA key lives in this Mac's login Keychain (created once via
# `generate_keys`, which also printed the SUPublicEDKey now embedded in
# TokenGrassMac/Info.plist — don't regenerate unless you're prepared to ship a
# new public key to every existing install).

./scripts/update-appcast.sh build/TokenGrass.dmg <version> <build> \
  "https://github.com/shw1606/token-grass/releases/tag/v<version>" 14.0

git add docs/appcast.xml
git commit -m "Release v<version>"
git push   # GitHub Pages redeploys automatically; existing installs pick it up
           # on their next check (SUScheduledCheckInterval, ~daily) or via the
           # menu's "업데이트 확인" button.
```

## iOS app + widget (App Store)

1. Set the signing team on the `TokenGrass` and `TokenGrassWidget` targets (Xcode
   auto-manages provisioning once the team is set).
2. Archive: Xcode → Product → Archive (or `xcodebuild archive`).
3. Distribute via Organizer → App Store Connect → upload.
4. In App Store Connect: fill in the listing (see `docs/APPSTORE.md`), attach
   screenshots, set **Privacy → Data Not Collected** (the app has no backend and
   collects nothing), submit for review or push to TestFlight.

## iCloud sync

The iCloud key-value sync between the Mac companion and the iPhone widget only
activates once both targets are signed with the paid team (the free Personal team
can't enable the iCloud capability). The entitlements are already in place; no code
change is needed — just set the team and rebuild.
