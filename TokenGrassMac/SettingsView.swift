import SwiftUI
import AppKit
import TokenGrassCore

/// The app's Settings window: account/login, display mode, and options — all
/// the controls that used to crowd the menu-bar popover.
struct SettingsView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var updater: UpdaterViewModel

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var showingLogin = false
    @State private var pastedCode = ""
    @State private var loginError: String?
    @State private var isConnecting = false

    @AppStorage("tokengrass.displayMode") private var displayModeRaw = GrassDisplayMode.grass.rawValue
    private var displayModeBinding: Binding<GrassDisplayMode> {
        Binding(
            get: { GrassDisplayMode(rawValue: displayModeRaw) ?? .grass },
            set: { displayModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("계정") { account }
            Section("표시") {
                Picker("보기", selection: displayModeBinding) {
                    Text("잔디").tag(GrassDisplayMode.grass)
                    Text("달력").tag(GrassDisplayMode.calendar)
                }
                .pickerStyle(.segmented)
            }
            Section("옵션") {
                Toggle("로그인 시 자동 실행", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in LoginItem.setEnabled(on) }
                Toggle("자동 업데이트 확인 (하루 1회)", isOn: $updater.automaticallyChecksForUpdates)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Account

    @ViewBuilder private var account: some View {
        if service.isStandalone {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("내 Claude 계정으로 로그인됨").font(.callout.weight(.medium))
                    Text("이 앱이 사용량을 직접 갱신해요. Claude Code를 켜두지 않아도 만료되지 않습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("로그아웃") { service.signOutStandalone() }
            }
        } else if showingLogin {
            loginCard
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Claude 계정으로 로그인하면 이 앱이 사용량을 직접, 스스로 갱신합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Button { beginLogin() } label: {
                    Label("내 Claude 계정으로 로그인", systemImage: "person.crop.circle.badge.checkmark")
                }
            }
        }
        if let loginError {
            Text(loginError).font(.caption).foregroundStyle(.red)
        }
    }

    private var loginCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("1) 브라우저에서 승인 후 표시되는 코드를 복사하세요.", systemImage: "1.circle")
                .font(.caption)
            Button("승인 페이지 다시 열기") { openAuthorize() }
                .controlSize(.small)
            Label("2) 코드 붙여넣기", systemImage: "2.circle").font(.caption)
            HStack(spacing: 6) {
                TextField("code#state", text: $pastedCode)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospaced())
                if isConnecting {
                    ProgressView().controlSize(.small)
                } else {
                    Button("연결") { connect() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(pastedCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            Button("취소") { cancelLogin() }
                .buttonStyle(.link).controlSize(.small)
        }
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
}
