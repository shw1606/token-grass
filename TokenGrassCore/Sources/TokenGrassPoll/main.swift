import Foundation
import TokenGrassCore

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("✗ " + message + "\n").utf8))
    exit(1)
}

print("TokenGrass poller — Keychain 읽고 /api/oauth/usage 1회 폴링…\n")

// 1) credentials from Keychain (triggers an Allow prompt the first time)
let credentials: ClaudeCredentials
do {
    credentials = try Keychain.readClaudeCode()
} catch {
    fail("\(error)\n  → Keychain 'Claude Code-credentials' 접근을 Allow 했는지 확인하세요.")
}

if let expiresAt = credentials.expiresAt {
    let minutes = Int(expiresAt.timeIntervalSinceNow / 60)
    print("access token: \(minutes >= 0 ? "유효, ~\(minutes)분 남음" : "만료됨 (\(-minutes)분 지남)")")
}

// 2) poll usage
let response: UsageAPI.Response
do {
    response = try UsageAPI.fetchUsage(accessToken: credentials.accessToken)
} catch {
    fail("\(error)")
}

guard response.status == 200 else {
    if response.status == 401 {
        fail("HTTP 401 — access token 만료. refresh(S2)는 다음 단계. 우선 `claude`를 한 번 쓰면 토큰이 갱신됩니다.")
    }
    let body = String(data: response.body, encoding: .utf8) ?? ""
    fail("HTTP \(response.status): \(body.prefix(300))")
}

// 3) parse
let usage: UsageResponse
do {
    usage = try UsageResponse.parse(response.body)
} catch {
    fail("응답 파싱 실패: \(error)")
}

let resetString = ISO8601DateFormatter().string(from: usage.sevenDay.resetsAt)
print(String(
    format: "five_hour: %.1f%%   seven_day: %.1f%% (resets %@)\n",
    usage.fiveHour.utilization, usage.sevenDay.utilization, resetString
))

// 4) accumulate (persisted across runs)
var accumulator = UsageAccumulator(state: StateStore.load(), calendar: .grass())
accumulator.apply(utilization: usage.sevenDay.utilization, resetAt: usage.sevenDay.resetsAt, now: Date())
do {
    try StateStore.save(accumulator.state)
} catch {
    fail("상태 저장 실패: \(error)")
}

// 5) print accumulated daily intensity
let daily = accumulator.state.daily
if daily.isEmpty {
    print("첫 폴 = 베이스라인 설정 완료 (과거 백필 없음).")
    print("→ Claude를 좀 쓴 뒤 이 명령을 다시 실행하면, seven_day 증분이 일별로 쌓입니다.")
} else {
    print("누적 일별 사용강도 (% of weekly limit) — 최근:")
    for key in daily.keys.sorted().suffix(14) {
        let value = daily[key] ?? 0
        let bar = String(repeating: "█", count: min(50, Int((value * 4).rounded())))
        print(String(format: "  %@  %6.2f%%  %@", key, value, bar))
    }
}
print("\nstate file: \(StateStore.fileURL.path)")
