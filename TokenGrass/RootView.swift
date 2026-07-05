import SwiftUI
import TokenGrassCore

/// Phase A/B screen: demo grass + stats + home-screen widget previews. This is
/// what an App Review reviewer sees with no token (DESIGN §5.1, APPSTORE 2.1).
/// Token connect / sync / disconnect arrive in a later phase.
struct RootView: View {
    @ObservedObject var sync: ICloudSync

    private var isReal: Bool { sync.snapshot != nil }
    private var snapshot: UsageSnapshot { sync.snapshot ?? DemoData.snapshot(weeks: 53) }

    private var usage: [String: Int] { snapshot.usageByDay }
    private var yearGrid: GrassGrid { DateGrid.makeGrid(usage: usage, weeks: 53) }
    private var previewGrid: GrassGrid { DateGrid.makeGrid(usage: usage, weeks: 26) }

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
                GrassChartView(grid: yearGrid, theme: .claudeOrange, cellSize: 11, spacing: 2.5, showMonthLabels: true, onDark: true)
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

    // MARK: - Widget previews (mirror the real widget: dark, orange, packed, no text)

    private var widgetPreviews: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("On your home screen").font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                mockCard { PackedGrassView(grid: previewGrid, theme: .claudeOrange) }
                    .frame(width: 155, height: 155)
                Text("2×2").font(.caption2).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                mockCard { PackedGrassView(grid: previewGrid, theme: .claudeOrange) }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(2.05, contentMode: .fit)
                Text("4×2").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func mockCard(@ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(16) // ≈ 1 cell, matching the widget's system content margin
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GrassTheme.darkSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    // MARK: - Status & footer

    @ViewBuilder private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isReal {
                Label("Synced from your Mac", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
                Text("Your grass updates automatically from the TokenGrass app on your Mac, over iCloud. No account, no servers.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Label("Showing demo data", systemImage: "circle.dashed")
                    .font(.subheadline.weight(.medium))
                Text("Want your real grass? Install the free TokenGrass app on the Mac where you use Claude Code. It reads your usage there and syncs it to your phone over iCloud. No login, no servers, nothing sent to us.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Link("Get the Mac app", destination: URL(string: "https://github.com/shw1606/token-grass")!)
                    .font(.footnote.weight(.medium))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardBackground()
    }

    private var demoBadge: some View {
        Text(isReal ? "SYNCED" : "DEMO")
            .font(.caption2.bold())
            .foregroundStyle(isReal ? Color.green : Color.primary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background((isReal ? Color.green : Color.yellow).opacity(0.22), in: Capsule())
    }

    private var disclaimer: some View {
        Text("Independent open-source project, not affiliated with or endorsed by Anthropic. \"Claude\" and \"Claude Code\" are trademarks of Anthropic.")
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
    RootView(sync: ICloudSync())
}
