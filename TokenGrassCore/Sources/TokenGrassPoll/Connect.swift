import Foundation
import TokenGrassCore

/// Validates the chosen auth: the app runs the GENUINE `claude setup-token`
/// (which isn't blocked, unlike our own OAuth client), captures the long-lived
/// token it prints, and polls usage. The macOS GUI app wraps this in one button.
func runConnect() {
    guard let claudePath = findClaude() else {
        fail("`claude` 바이너리를 못 찾았습니다. Claude Code 설치 후 다시 시도하세요.")
    }
    print("found claude: \(claudePath)")
    print("실행: `claude setup-token` — 브라우저가 열리면 로그인·승인하세요.\n----")

    let (output, exitCode) = runClaudeSetupToken(at: claudePath)
    print("\n----")
    guard exitCode == 0 else { fail("claude setup-token 종료코드 \(exitCode)") }
    guard let token = extractToken(from: output) else {
        fail("출력에서 토큰(sk-ant-…)을 못 찾았습니다. 마지막 출력:\n\(String(output.suffix(400)))")
    }

    let tokens = OAuthTokens(
        accessToken: token, refreshToken: "",
        expiresAt: Date().addingTimeInterval(365 * 24 * 3600), scope: nil
    )
    try? TokenStore.save(tokens)
    print("\n✓ 토큰 캡처: \(token.prefix(16))…  저장: \(TokenStore.fileURL.path)")

    print("검증: 그 토큰으로 usage 폴…")
    do {
        let response = try UsageAPI.fetchUsage(accessToken: token)
        guard response.status == 200 else {
            fail("usage HTTP \(response.status): \(String(data: response.body, encoding: .utf8)?.prefix(200) ?? "")")
        }
        let usage = try UsageResponse.parse(response.body)
        print(String(format: "✓ five_hour %.1f%%   seven_day %.1f%%", usage.fiveHour.utilization, usage.sevenDay.utilization))
        print("\n🎉 앱이 setup-token 실행 → 토큰 캡처 → usage 동작 확인. GUI 앱이 이걸 버튼 하나로 감쌉니다.")
    } catch {
        fail("usage 검증 실패: \(error)")
    }
}

/// Runs `claude setup-token`, capturing combined stdout+stderr while echoing it
/// live so the user sees the prompts / browser instructions.
private func runClaudeSetupToken(at path: String) -> (output: String, exitCode: Int32) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = ["setup-token"]
    process.standardInput = FileHandle.standardInput

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    let lock = NSLock()
    var captured = Data()
    pipe.fileHandleForReading.readabilityHandler = { handle in
        let chunk = handle.availableData
        guard !chunk.isEmpty else { return }
        lock.lock(); captured.append(chunk); lock.unlock()
        FileHandle.standardError.write(chunk) // echo to user
    }

    do { try process.run() } catch { return ("", -1) }
    process.waitUntilExit()
    pipe.fileHandleForReading.readabilityHandler = nil
    let rest = pipe.fileHandleForReading.readDataToEndOfFile()
    lock.lock(); captured.append(rest); lock.unlock()
    return (String(data: captured, encoding: .utf8) ?? "", process.terminationStatus)
}

private func extractToken(from output: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: "sk-ant-[A-Za-z0-9_-]{20,}") else { return nil }
    let range = NSRange(output.startIndex..., in: output)
    let tokens = regex.matches(in: output, range: range).compactMap {
        Range($0.range, in: output).map { String(output[$0]) }
    }
    return tokens.max(by: { $0.count < $1.count }) // longest sk-ant match
}

private func findClaude() -> String? {
    let fm = FileManager.default
    let candidates = [
        "\(NSHomeDirectory())/.local/bin/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        "/usr/bin/claude",
    ]
    for path in candidates where fm.isExecutableFile(atPath: path) { return path }

    // Fall back to the user's login-shell PATH.
    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: shell)
    process.arguments = ["-lc", "command -v claude"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    process.waitUntilExit()
    let resolved = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if let resolved, !resolved.isEmpty, fm.isExecutableFile(atPath: resolved) { return resolved }
    return nil
}
