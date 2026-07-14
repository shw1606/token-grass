import SwiftUI
import TokenGrassCore

/// Home screen. Three data sources, in priority order:
/// standalone (this phone signed in with Claude) → Mac-synced (iCloud) → demo.
struct RootView: View {
    @ObservedObject var service: PhoneUsageService
    @State private var showLogin = false

    /// The Mac-download landing page (opened on the Mac, or shared to it).
    private let setupURL = URL(string: "https://shw1606.github.io/token-grass")!

    private enum Source { case standalone, macSynced, demo }
    private var source: Source {
        if service.isLoggedIn { return .standalone }
        if service.snapshot != nil { return .macSynced }
        return .demo
    }

    private var snapshot: UsageSnapshot { service.snapshot ?? DemoData.snapshot(weeks: 53) }
    private var usage: [String: Int] { snapshot.usageByDay }
    private var yearGrid: GrassGrid { DateGrid.makeGrid(usage: usage, weeks: 53) }
    private var previewGrid: GrassGrid { DateGrid.makeGrid(usage: usage, weeks: 26) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    yearCard
                    if source == .standalone { liveUsageCard }
                    statsRow
                    widgetPreviews
                    statusCard
                    disclaimer
                }
                .padding()
            }
            .refreshable { await service.sync(force: true) }
            .navigationTitle("TokenGrass")
        }
        .sheet(isPresented: $showLogin) {
            ClaudeLoginView(service: service)
        }
        #if DEBUG
        // UI-test hook: TG_UI=login auto-opens the sign-in sheet (no tap needed
        // for headless simulator screenshots).
        .onAppear {
            if ProcessInfo.processInfo.environment["TG_UI"] == "login" { showLogin = true }
        }
        #endif
    }

    // MARK: - Year chart

    private var yearCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your grass").font(.headline)
                Spacer()
                sourceBadge
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

    // MARK: - Live usage (standalone mode)

    private var liveUsageCard: some View {
        HStack(spacing: 12) {
            liveTile("5-hour session", service.fiveHour, resetsAt: service.fiveHourResetsAt)
            liveTile("7-day", service.sevenDay, resetsAt: service.sevenDayResetsAt)
            // Per-model weekly (e.g. Fable) — only when the plan scopes one.
            if let model = service.scopedWeeklyModel {
                liveTile("\(model) weekly", service.scopedWeekly, resetsAt: service.scopedWeeklyResetsAt)
            }
        }
    }

    private func liveTile(_ label: String, _ percent: Double, resetsAt: Date?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text("\(Int(percent))%")
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            if let resetsAt {
                Text("resets \(resetsAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            switch source {
            case .standalone:
                standaloneStatus
            case .macSynced:
                macSyncedStatus
            case .demo:
                demoStatus
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardBackground()
    }

    @ViewBuilder private var standaloneStatus: some View {
        if service.needsRelogin {
            Label("Session expired", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.orange)
            Text("Sign in again to keep your grass growing. Your history is safe.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Sign in again") { showLogin = true }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.91, green: 0.44, blue: 0.13))
                .controlSize(.small)
        } else {
            Label("Connected to your Claude account", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.green)
            Text("This iPhone reads your usage straight from Anthropic — no Mac needed, no third-party servers. Pull down to refresh.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let error = service.lastError {
                Label(error, systemImage: "wifi.exclamationmark")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            HStack {
                if let last = service.lastSync {
                    Text("Synced \(last.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Sign out") { service.signOut() }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var macSyncedStatus: some View {
        Label("Synced over iCloud", systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.green)
        Text("Your grass stays up to date over iCloud — from the TokenGrass app on your Mac, or from this iPhone's own history. No servers.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        Divider().padding(.vertical, 2)
        Text("Want this iPhone to update on its own too?")
            .font(.caption)
            .foregroundStyle(.secondary)
        Button {
            showLogin = true
        } label: {
            Label("Sign in with Claude", systemImage: "person.crop.circle.badge.checkmark")
                .font(.footnote.weight(.medium))
        }
    }

    @ViewBuilder private var demoStatus: some View {
        Label("Make it yours", systemImage: "sparkles")
            .font(.subheadline.weight(.semibold))
        Text("This grass is a demo. Sign in with your Claude account and this iPhone will track your real usage by itself.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        Button {
            showLogin = true
        } label: {
            Label("Sign in with Claude", systemImage: "person.crop.circle.badge.checkmark")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(red: 0.91, green: 0.44, blue: 0.13))

        Divider().padding(.vertical, 2)

        Label("Prefer the Mac companion?", systemImage: "macbook.and.iphone")
            .font(.footnote.weight(.medium))
        Text("It reads Claude Code usage on your Mac and syncs here over iCloud — no sign-in at all.")
            .font(.caption)
            .foregroundStyle(.secondary)

        // The download lives on the Mac, so give an address to open there
        // plus a one-tap way to send the link across.
        VStack(alignment: .leading, spacing: 3) {
            Text("On your Mac, open").font(.caption2).foregroundStyle(.secondary)
            Text("shw1606.github.io/token-grass")
                .font(.footnote.weight(.semibold)).monospaced()
                .foregroundStyle(Color(red: 0.91, green: 0.44, blue: 0.13))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

        ShareLink(item: setupURL) {
            Label("Send the link to my Mac", systemImage: "square.and.arrow.up")
                .font(.footnote.weight(.medium))
        }
    }

    private var sourceBadge: some View {
        let (text, color): (String, Color) = {
            switch source {
            case .standalone: return ("LIVE", .green)
            case .macSynced: return ("SYNCED", .green)
            case .demo: return ("DEMO", .yellow)
            }
        }()
        return Text(text)
            .font(.caption2.bold())
            .foregroundStyle(source == .demo ? Color.primary : color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.22), in: Capsule())
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
    RootView(service: PhoneUsageService.shared)
}
