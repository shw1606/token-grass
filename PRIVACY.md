# Privacy Policy

_Last updated: 2026-07-05_

**TokenGrass does not collect any data.** There is no backend, no account, and
no analytics. Nothing you do in the app or the companion is sent to us or to any
third party we control — because there is no "us" server to send it to.

## What the app handles, and where it stays

TokenGrass shows your Claude Code usage as a contribution-graph ("grass") widget.
The data path is entirely on your own devices plus Apple's iCloud:

- **On your Mac**, the free TokenGrass companion reads your existing Claude Code
  usage. Your Claude Code login/token is read from the macOS Keychain and is used
  only to fetch your usage from Anthropic's servers directly. **The token never
  leaves your Mac** and is never stored by TokenGrass.
- The companion computes a small daily "usage intensity" summary (a few kilobytes:
  dates and percentages — **no token counts, no message content, no credentials**)
  and writes it to your private **iCloud key-value store**.
- **On your iPhone**, the app and widget read that summary from your iCloud and
  render the grass. That's it.

We never receive, store, or have access to any of this. iCloud sync is handled by
Apple under your Apple ID and your [iCloud privacy terms](https://www.apple.com/legal/privacy/).

## Third parties

- **Anthropic** — the Mac companion calls Anthropic's usage endpoint directly with
  your own Claude credentials to read your own usage. This is between you and
  Anthropic; see Anthropic's privacy policy. TokenGrass is an independent project
  and is not affiliated with Anthropic.
- **Apple iCloud** — used only to sync the small usage summary between your own
  devices.

No advertising, no tracking, no third-party SDKs, no crash reporting.

## Data deletion

To remove all data: delete the app from your iPhone and quit/remove the Mac
companion. To also clear the synced summary, remove TokenGrass data from iCloud in
your device settings. Because nothing is stored on any server, there is nothing
else to delete.

## Contact

Questions? Open an issue at
<https://github.com/shw1606/token-grass> or email shw4008@gmail.com.
