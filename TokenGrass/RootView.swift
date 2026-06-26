import SwiftUI
import TokenGrassCore

/// Phase A/B screen: demo grass + stats + home-screen widget previews. This is
/// what an App Review reviewer sees with no token (DESIGN §5.1, APPSTORE 2.1).
/// Token connect / sync / disconnect arrive in a later phase.
struct RootView: View {
    private let snapshot = DemoData.snapshot(weeks: 53)

    private var usage: [String: Int] { snapshot.usageByDay }
    private var yearGrid: GrassGrid { DateGrid.makeGrid(usage: usage, weeks: 53) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    yearCard
                    statsRow
                    widgetPreviews
                    statusCard
                    disclaimer
                }
                .padding()
            }
            .navigationTitle("TokenGrass")
        }
    }

    // MARK: - Year chart

    private var yearCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your grass").font(.headline)
                Spacer()
                demoBadge
            }
            ScrollView(.horizontal, showsIndicators: false) {
                GrassChartView(grid: yearGrid, theme: .githubGreen, cellSize: 11, spacing: 2.5, showMonthLabels: true)
                    .padding(.vertical, 2)
            }
            .defaultScrollAnchor(.trailing)
        }
        .padding()
        .cardBackground()
    }

    // MARK: - Stats

    private var statsRow: some View {
        let grid = yearGrid
        return HStack(spacing: 12) {
            StatTile(label: "Today", value: TokenFormat.compact(grid.todayTokens))
            StatTile(label: "7 days", value: TokenFormat.compact(grid.lastWeekTokens))
            StatTile(label: "Total", value: TokenFormat.compact(grid.totalTokens))
            StatTile(label: "Active", value: "\(grid.activeDayCount)d")
        }
    }

    // MARK: - Widget previews

    private var widgetPreviews: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("On your home screen").font(.headline)
            HStack(alignment: .top, spacing: 16) {
                widgetMock(label: "Small") {
                    FittedGrassView(grid: DateGrid.makeGrid(usage: usage, weeks: 17), showMonthLabels: false)
                }
                .frame(width: 150, height: 150)

                widgetMock(label: "Medium") {
                    FittedGrassView(grid: DateGrid.makeGrid(usage: usage, weeks: 30), showMonthLabels: true)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
            }
        }
    }

    private func widgetMock(label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Status & footer

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Not connected", systemImage: "circle.dashed")
                .font(.subheadline.weight(.medium))
            Text("Paste your Claude Code token to grow your real grass. Coming in a later phase — this build shows demo data.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardBackground()
    }

    private var demoBadge: some View {
        Text("DEMO")
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.yellow.opacity(0.25), in: Capsule())
    }

    private var disclaimer: some View {
        Text("Independent open-source project — not affiliated with or endorsed by Anthropic. \"Claude\" and \"Claude Code\" are trademarks of Anthropic.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}

private struct StatTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private extension View {
    func cardBackground() -> some View {
        background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    RootView()
}
