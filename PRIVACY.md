# Privacy Policy

_Last updated: 2026-07-05_ · [한국어](PRIVACY.ko.md)

**TokenGrass collects nothing.** There is no backend, no account, and no
analytics. Nothing you do in the app or the Mac app is sent to us or to any third
party we control, because there is no "us" server to send it to.

## What the app handles, and where it stays

TokenGrass shows your Claude Code usage as a contribution-graph ("grass") widget.
Everything happens on your own devices, plus Apple's iCloud:

- **On your Mac**, the free TokenGrass app reads your existing Claude Code usage.
  Your Claude Code login is read from the macOS Keychain and used only to fetch
  your usage from Anthropic directly. Your token never leaves your Mac, and
  TokenGrass never stores it.
- The Mac app works out a small daily "usage intensity" summary (a few kilobytes:
  just dates and percentages, with **no token counts, no message content, and no
  credentials**) and writes it to your private **iCloud key-value store**.
- **On your iPhone**, the app and widget read that summary from your iCloud and
  draw the grass. That's the whole story.

We never receive, store, or have access to any of this. iCloud sync is handled by
Apple under your Apple ID and your
[iCloud privacy terms](https://www.apple.com/legal/privacy/).

## Third parties

- **Anthropic**: the Mac app calls Anthropic's usage endpoint directly, with your
  own Claude credentials, to read your own usage. That's between you and Anthropic
  (see Anthropic's privacy policy). TokenGrass is an independent project and is not
  affiliated with Anthropic.
- **Apple iCloud**: used only to sync the small usage summary between your own
  devices.

No advertising, no tracking, no third-party SDKs, no crash reporting.

## Deleting your data

To remove everything, delete the app from your iPhone and quit or remove the Mac
app. To also clear the synced summary, remove TokenGrass data from iCloud in your
device settings. Since nothing is stored on any server, there's nothing else to
delete.

## Contact

Questions? Open an issue at
<https://github.com/shw1606/token-grass> or email shw4008@gmail.com.
