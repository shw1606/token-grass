import WidgetKit
import SwiftUI
import TokenGrassCore

struct TokenGrassWidget: Widget {
    private let kind = "TokenGrassWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            GrassWidgetView(entry: entry)
                .containerBackground(GrassTheme.darkSurface, for: .widget)
        }
        .configurationDisplayName("TokenGrass")
        .description("Your Claude Code token usage as a contribution graph.")
        .supportedFamilies([.systemSmall, .systemMedium]) // 2×2 and 4×2 only
    }
}

/// Just grass, edge to edge. No text. The number of weeks shown adapts to the
/// widget width (≈7 columns small, ≈16 medium); 26 weeks gives enough history.
struct GrassWidgetView: View {
    let entry: GrassEntry

    var body: some View {
        let grid = DateGrid.makeGrid(usage: entry.snapshot.usageByDay, weeks: 26)
        PackedGrassView(grid: grid, theme: .claudeOrange, gapRatio: 0.28)
    }
}
