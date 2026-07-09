import SwiftUI
import UIKit
import TokenGrassCore

/// "Sign in with Claude" sheet. Anthropic's OAuth callback is a page that
/// *shows* the authorization code (no app redirect), so the flow is:
/// open claude.ai in Safari → approve → copy the code → come back and paste.
struct ClaudeLoginView: View {
    @ObservedObject var service: PhoneUsageService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var authorizeURL: URL?
    @State private var pastedCode = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var openedBrowser = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    intro
                    stepOne
                    stepTwo
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    privacyNote
                }
                .padding()
            }
            .navigationTitle("Sign in with Claude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear { authorizeURL = service.beginLogin() }
    }

    private var intro: some View {
        Text("Connect your Claude account so this iPhone can read your usage on its own — no Mac needed.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var stepOne: some View {
        VStack(alignment: .leading, spacing: 8) {
            stepLabel(1, "Approve in Safari")
            Text("You'll land on claude.ai. Log in if asked, approve, and the page will show you a code.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                if let authorizeURL {
                    openURL(authorizeURL)
                    openedBrowser = true
                }
            } label: {
                Label("Open claude.ai", systemImage: "safari")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.91, green: 0.44, blue: 0.13))
        }
    }

    private var stepTwo: some View {
        VStack(alignment: .leading, spacing: 8) {
            stepLabel(2, "Paste the code")
            HStack(spacing: 8) {
                TextField("Code from claude.ai", text: $pastedCode)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.footnote.monospaced())
                Button {
                    if let clip = UIPasteboard.general.string {
                        pastedCode = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
            }
            Button {
                connect()
            } label: {
                Group {
                    if isWorking {
                        ProgressView()
                    } else {
                        Text("Connect")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(pastedCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
        }
        .opacity(openedBrowser ? 1 : 0.55)
    }

    private var privacyNote: some View {
        Text("Your sign-in stays between this iPhone and Anthropic. Tokens are stored in the iOS Keychain and are only ever sent to api.anthropic.com — no third-party servers.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private func stepLabel(_ number: Int, _ title: String) -> some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(Color(red: 0.91, green: 0.44, blue: 0.13).opacity(0.18), in: Circle())
            Text(title).font(.subheadline.weight(.semibold))
        }
    }

    private func connect() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await service.completeLogin(pastedCode: pastedCode)
                dismiss()
            } catch let error as ClaudeNetError {
                errorMessage = friendlyExchangeError(error)
            } catch {
                errorMessage = "Something went wrong. Try opening claude.ai again for a fresh code."
            }
            isWorking = false
        }
    }

    private func friendlyExchangeError(_ error: ClaudeNetError) -> String {
        switch error.status {
        case 400:
            return "That code didn't work — codes are single-use and expire quickly. Tap “Open claude.ai” again and paste the fresh code."
        case 429:
            return "Anthropic is rate-limiting right now. Wait a minute and try again."
        default:
            return "Sign-in failed (\(error)). Try again with a fresh code."
        }
    }
}
