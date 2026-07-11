import SwiftUI
import TokenGrassCore

struct MenuContentView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var updater: UpdaterViewModel
    @State private var launchAtLogin = LoginItem.isEnabled
    /// Stable anchor for the countdown's TimelineView (never `.now`, which spins).
    @State private var timelineAnchor = Date()
    @State private var showingLogin = false
    @State private var pastedCode = ""
    @State private var loginError: String?
    @State private var isConnecting = false
    @AppStorage("tokengrass.displayMode") private var displayModeRaw = GrassDisplayMode.grass.rawValue
    private var displayMode: GrassDisplayMode { GrassDisplayMode(rawValue: displayModeRaw) ?? .grass }
    private var displayModeBinding: Binding<GrassDisplayMode> {
        Binding(get: { displayMode }, set: { displayModeRaw = $0.rawValue })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            grassSection
            stats
            accountSection
            loginToggle
            Divider()
            footer
        }
        .padding(14)
        .frame(width: displayMode == .calendar && service.hasData ? 220 : 320)
    }

    // MARK: - Account (standalone login)

    @ViewBuilder private var accountSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if service.isStandalone {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.caption)
                    Text("내 Claude 계정으로 로그인됨").font(.caption)
                    Spacer()
                    Button("로그아웃") { service.signOutStandalone() }
                        .buttonStyle(.link).controlSize(.small)
                }
                Text("이 앱이 사용량을 직접 갱신해요. Claude Code를 켜두지 않아도 만료되지 않습니다.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else if showingLogin {
                loginCard
            } else {
                Button { beginLogin() } label: {
                    Label("내 Claude 계정으로 직접 로그인", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.caption)
                }
                .controlSize(.small)
                Text("지금은 Claude Code 로그인에 얹혀 있어요. 직접 로그인하면 앱이 스스로 토큰을 갱신해 “로그인 만료”가 사라집니다.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let loginError {
                Text(loginError).font(.caption2).foregroundStyle(.red).lineLimit(3)
            }
        }
    }

    private var loginCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("1) 브라우저에서 승인 후 표시되는 코드를 복사하세요.")
                .font(.caption2).foregroundStyle(.secondary)
            Button("승인 페이지 다시 열기") { openAuthorize() }
                .controlSize(.small)
            Text("2) 코드 붙여넣기").font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField("code#state", text: $pastedCode)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                if isConnecting {
                    ProgressView().controlSize(.small)
                } else {
                    Button("연결") { connect() }
                        .controlSize(.small)
                        .disabled(pastedCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            Button("취소") { cancelLogin() }
                .buttonStyle(.link).controlSize(.small)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func beginLogin() {
        openAuthorize()
        showingLogin = true
        loginError = nil
    }

    private func openAuthorize() {
        NSWorkspace.shared.open(service.beginStandaloneLogin())
    }

    private func cancelLogin() {
        showingLogin = false
        pastedCode = ""
        loginError = nil
    }

    private func connect() {
        isConnecting = true
        loginError = nil
        Task {
            do {
                try await service.completeStandaloneLogin(pastedCode: pastedCode)
                showingLogin = false
                pastedCode = ""
            } catch {
                loginError = "연결 실패 — 코드는 한 번만 쓸 수 있어요. ‘승인 페이지 다시 열기’로 새 코드를 받아 다시 붙여넣어 주세요."
            }
            isConnecting = false
        }
    }

    private var loginToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("로그인 시 자동 실행", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.caption)
                .onChange(of: launchAtLogin) { _, enabled in LoginItem.setEnabled(enabled) }
            Toggle("자동 업데이트 확인", isOn: $updater.automaticallyChecksForUpdates)
                .toggleStyle(.checkbox)
                .font(.caption)
        }
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
            VStack(alignment: .leading, spacing: 8) {
                Text("Claude Code 로그인이 필요합니다").font(.subheadline.weight(.medium))
                Text("Mac에서 Claude Code에 로그인돼 있어야 사용량을 읽습니다. 터미널에서 `claude` 를 한 번 실행해 로그인하세요.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("터미널 열기") { openTerminal() }
                    Button("다시 확인") { Task { await service.sync() } }
                        .disabled(service.isBusy)
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .authExpired(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text("로그인 만료").font(.subheadline.weight(.medium)).foregroundStyle(.orange)
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                HStack {
                    if service.isStandalone {
                        Button("다시 로그인") { beginLogin() }
                    } else {
                        Button("터미널 열기") { openTerminal() }
                    }
                    Button("다시 시도") { Task { await service.sync() } }
                        .disabled(service.isBusy)
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .error(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text("동기화 오류").font(.subheadline.weight(.medium)).foregroundStyle(.red)
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                Button("다시 시도") { Task { await service.sync() } }
                    .disabled(service.isBusy)
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .ok, .unknown:
            if service.hasData {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("", selection: displayModeBinding) {
                        Text("잔디").tag(GrassDisplayMode.grass)
                        Text("달력").tag(GrassDisplayMode.calendar)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

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
                }
            } else {
                Text("데이터 수집 중… 사용할수록 잔디가 채워집니다 🌱")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 70)
            }
        }
    }

    private func openTerminal() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
    }

    private var stats: some View {
        HStack(alignment: .top) {
            statTile("5시간 세션", service.fiveHour) {
                // Live countdown — 5-hour window is close, so relative reads best.
                // Anchor the schedule to a FIXED date: `.now` is re-evaluated every
                // render, which keeps invalidating the schedule and spins the CPU
                // at 100%. A stable @State anchor ticks every 30s as intended.
                if let resetsAt = service.fiveHourResetsAt {
                    TimelineView(.periodic(from: timelineAnchor, by: 30)) { context in
                        resetLabel(countdownCaption(resetsAt, now: context.date))
                    }
                }
            }
            Spacer()
            statTile("7일", service.sevenDay) {
                // Absolute time — the weekly reset is days out, so a clock time is clearer.
                if let resetsAt = service.sevenDayResetsAt {
                    resetLabel("\(Self.resetFormatter.string(from: resetsAt)) 리셋")
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
            Button("지금 동기화") { Task { await service.sync() } }
                .disabled(service.isBusy)
            Button("종료") { NSApplication.shared.terminate(nil) }
        }
        .controlSize(.small)
    }
}
