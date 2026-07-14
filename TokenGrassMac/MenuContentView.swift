import SwiftUI
import TokenGrassCore

/// The menu-bar popover: status + the grass/calendar visualization + live
/// stats. All settings (login, display mode, options) live in the separate
/// Settings window, reachable via the gear button.
struct MenuContentView: View {
    @ObservedObject var service: UsageService
    /// Opens the app's Settings window (owned by AppDelegate).
    var onOpenSettings: () -> Void

    /// Stable anchor for the countdown's TimelineView (never `.now`, which spins).
    @State private var timelineAnchor = Date()
    @AppStorage("tokengrass.displayMode") private var displayModeRaw = GrassDisplayMode.grass.rawValue
    private var displayMode: GrassDisplayMode { GrassDisplayMode(rawValue: displayModeRaw) ?? .grass }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            grassSection
            stats
            Divider()
            footer
        }
        .padding(14)
        .frame(width: displayMode == .calendar && service.hasData ? 220 : 320)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "leaf.fill")
                .foregroundStyle(Color(red: 0.91, green: 0.44, blue: 0.13))
            Text("TokenGrass").font(.headline)
            Spacer()
            statusDot
        }
    }

    @ViewBuilder private var statusDot: some View {
        let color: Color = {
            switch service.connection {
            case .ok: return .green
            case .notConnected, .authExpired: return .orange
            case .error: return .red
            case .unknown: return .gray
            }
        }()
        Circle().fill(color).frame(width: 8, height: 8)
    }

    @ViewBuilder private var grassSection: some View {
        switch service.connection {
        case .notConnected:
            promptCard(
                title: "로그인이 필요합니다",
                titleColor: .orange,
                message: "설정에서 Claude 계정으로 로그인하면 사용량이 채워집니다.",
                primary: ("설정 열기", onOpenSettings)
            )
        case .authExpired(let message):
            promptCard(
                title: "로그인 만료",
                titleColor: .orange,
                message: message,
                primary: ("설정 열기", onOpenSettings)
            )
        case .error(let message):
            promptCard(
                title: "동기화 오류",
                titleColor: .red,
                message: message,
                primary: ("다시 시도", { Task { await service.sync() } })
            )
        case .ok, .unknown:
            if service.hasData {
                Group {
                    switch displayMode {
                    case .grass:
                        PackedGrassView(grid: service.grid, theme: .claudeOrange)
                            .padding(10)
                            .frame(height: 130)
                    case .calendar:
                        MonthCalendarView(grid: service.grid, theme: .claudeOrange)
                            .frame(height: 240)
                    }
                }
                .background(GrassTheme.darkSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text("데이터 수집 중… 사용할수록 잔디가 채워집니다 🌱")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 70)
            }
        }
    }

    private func promptCard(
        title: String, titleColor: Color, message: String,
        primary: (label: String, action: () -> Void)
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(titleColor)
            Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            HStack {
                Button(primary.label, action: primary.action)
                Button("다시 시도") { Task { await service.sync() } }
                    .disabled(service.isBusy)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stats: some View {
        HStack(alignment: .top, spacing: 10) {
            statTile("5시간 세션", service.fiveHour) {
                // Live countdown — anchor the schedule to a FIXED date; `.now` is
                // re-evaluated every render, which keeps invalidating the schedule
                // and spins the CPU at 100%.
                if let resetsAt = service.fiveHourResetsAt {
                    TimelineView(.periodic(from: timelineAnchor, by: 30)) { context in
                        resetLabel(countdownCaption(resetsAt, now: context.date))
                    }
                }
            }
            Spacer(minLength: 0)
            statTile("7일", service.sevenDay) {
                if let resetsAt = service.sevenDayResetsAt {
                    resetLabel("\(Self.resetFormatter.string(from: resetsAt)) 리셋")
                }
            }
            // Per-model weekly (e.g. Fable) — only when the plan scopes one.
            if let model = service.scopedWeeklyModel {
                Spacer(minLength: 0)
                statTile("\(model) 주간", service.scopedWeekly) {
                    if let resetsAt = service.scopedWeeklyResetsAt {
                        resetLabel("\(Self.resetFormatter.string(from: resetsAt)) 리셋")
                    }
                }
            }
        }
    }

    private func statTile<Reset: View>(
        _ label: String, _ percent: Double, @ViewBuilder reset: () -> Reset
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text("\(Int(percent))%").font(.title3.weight(.semibold)).monospacedDigit()
            reset()
        }
    }

    private func resetLabel(_ text: String) -> some View {
        Text(text).font(.caption2).foregroundStyle(.secondary)
    }

    /// "2시간 13분 후 리셋" / "3일 후 리셋" / "곧 리셋".
    private func countdownCaption(_ date: Date, now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "곧 리셋" }
        let minutes = Int(seconds) / 60
        let hours = minutes / 60, mins = minutes % 60
        if hours >= 24 { return "\(hours / 24)일 후 리셋" }
        if hours > 0 { return "\(hours)시간 \(mins)분 후 리셋" }
        return "\(mins)분 후 리셋"
    }

    /// "7/4 15:00" — month/day + 24-hour clock, unambiguous across the week.
    private static let resetFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.setLocalizedDateFormatFromTemplate("M/d HH:mm")
        return f
    }()

    private var footer: some View {
        HStack {
            if let last = service.lastSync {
                Text("동기화 \(last.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("동기화 안 됨").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button { onOpenSettings() } label: { Image(systemName: "gearshape") }
                .help("설정")
            Button("동기화") { Task { await service.sync() } }
                .disabled(service.isBusy)
            Button("종료") { NSApplication.shared.terminate(nil) }
        }
        .controlSize(.small)
    }
}
