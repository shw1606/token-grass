# TokenGrass 🌱

> Your Claude Code token usage as a GitHub-style contribution graph — right on your iPhone home screen. Phone-only, free, open source.

TokenGrass turns your daily Claude Code token usage into a familiar contribution
heatmap and puts it **directly on your home screen as a widget** — no need to open
the app, no companion Mac required, no paywall.

**Status:** early scaffold (Phase A). The grass renders from demo data today; token
connection and live sync land in a later phase. See [`docs/ROADMAP.md`](docs/ROADMAP.md).

## Why

The closest app keeps its grass *inside* the app, needs a Mac companion to collect
data, and gates full history behind IAP. TokenGrass fills the exact gap: **widget-native
grass ∩ phone-only ∩ free**. Background and competitive analysis: [`docs/DESIGN.md`](docs/DESIGN.md).

## Project layout

```
token-grass/
├─ TokenGrassCore/      # Pure logic (Foundation-only) — models, grass math, demo data. Unit-tested.
├─ SharedUI/            # SwiftUI views shared by app + widget (GrassGridView, GrassTheme)
├─ TokenGrass/          # Main app target
├─ TokenGrassWidget/    # Widget extension target (WidgetKit)
├─ scripts/             # extract-token.sh onboarding helper
├─ docs/                # DESIGN / ROADMAP / APPSTORE
└─ project.yml          # XcodeGen project definition (source of truth)
```

Design choice: all grass math lives in `TokenGrassCore`, a plain Swift package with
**no SwiftUI/WidgetKit imports**, so it compiles and unit-tests without Xcode.

## Build

Requires Xcode 17+ (iOS 17 SDK) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen        # once
xcodegen generate            # creates TokenGrass.xcodeproj from project.yml
open TokenGrass.xcodeproj     # set your signing team, then run
```

| Identifier | Value |
|---|---|
| App bundle ID | `dev.yulebuilds.tokengrass` |
| Widget bundle ID | `dev.yulebuilds.tokengrass.widget` |
| App Group | `group.dev.yulebuilds.tokengrass` |
| Min target | iOS 17 |

## Test

The core grass logic is verified headlessly (no Xcode project needed):

```bash
cd TokenGrassCore && swift test
```

## Disclaimer

TokenGrass is an independent, open-source project and is not affiliated with,
endorsed by, or sponsored by Anthropic. "Claude" and "Claude Code" are trademarks
of Anthropic. This app uses unofficial endpoints and may stop working if those change.

## License

[MIT](LICENSE)
