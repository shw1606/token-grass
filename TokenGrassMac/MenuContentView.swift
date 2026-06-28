import SwiftUI
import TokenGrassCore

struct MenuContentView: View {
    @ObservedObject var service: UsageService
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            grassSection
            stats
            loginToggle
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    private var loginToggle: some View {
        Toggle("로그인 시 자동 실행", isOn: $launchAtLogin)
            .toggleStyle(.checkbox)
            .font(.caption)
            .onChange(of: launchAtLogin) { _, enabled in LoginItem.setEnabled(enabled) }
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
            case .notConnected: return .orange
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
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .error(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text("동기화 오류").font(.subheadline.weight(.medium)).foregroundStyle(.red)
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                Button("다시 시도") { Task { await service.sync() } }.controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .ok, .unknown:
            if service.hasData {
                PackedGrassView(grid: service.grid, theme: .claudeOrange)
                    .padding(10)
                    .frame(height: 130)
                    .background(GrassTheme.darkSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        HStack {
            statTile("5시간 세션", service.fiveHour)
            Spacer()
            statTile("7일", service.sevenDay)
        }
    }

    private func statTile(_ label: String, _ percent: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text("\(Int(percent))%").font(.title3.weight(.semibold)).monospacedDigit()
        }
    }

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
            Button("종료") { NSApplication.shared.terminate(nil) }
        }
        .controlSize(.small)
    }
}
