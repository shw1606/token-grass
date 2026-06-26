import WidgetKit
import SwiftUI
import TokenGrassCore

struct TokenGrassWidget: Widget {
    private let kind = "TokenGrassWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            GrassWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("TokenGrass")
        .description("Your Claude Code token usage as a contribution graph.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct GrassWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GrassEntry

    private var weeks: Int {
        switch family {
        case .systemSmall: return 17
        case .systemMedium: return 30
        default: return 53
        }
    }

    var body: some View {
        let grid = DateGrid.makeGrid(usage: entry.snapshot.usageByDay, weeks: weeks)
        VStack(alignment: .leading, spacing: 6) {
            header(for: grid)
            FittedGrassView(
                grid: grid,
                theme: .githubGreen,
                spacingRatio: 0.18,
                showMonthLabels: family != .systemSmall
            )
        }
    }

    private func header(for grid: GrassGrid) -> some View {
        HStack(spacing: 4) {
            Text(statLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(TokenFormat.compact(statValue(for: grid)))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            if entry.isDemo {
                Text("DEMO")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.yellow.opacity(0.3), in: Capsule())
            }
            Spacer(minLength: 0)
        }
    }

    private var statLabel: String {
        switch family {
        case .systemSmall: return "Today"
        case .systemMedium: return "7 days"
        default: return "Total"
        }
    }

    private func statValue(for grid: GrassGrid) -> Int {
        switch family {
        case .systemSmall: return grid.todayTokens
        case .systemMedium: return grid.lastWeekTokens
        default: return grid.totalTokens
        }
    }
}
