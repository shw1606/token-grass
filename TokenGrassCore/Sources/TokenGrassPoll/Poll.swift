import Foundation
import TokenGrassCore

/// Poll usage (via Claude Code's Keychain token) and accumulate. Kept for the
/// piggyback validation; the shipping app will use our own OAuth tokens instead.
func runPoll() {
    print("\n=== TokenGrass poll @ \(ISO8601DateFormatter().string(from: Date())) ===")

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

    let response: UsageAPI.Response
    do {
        response = try UsageAPI.fetchUsage(accessToken: credentials.accessToken)
    } catch {
        fail("\(error)")
    }

    guard response.status == 200 else {
        if response.status == 401 {
            fail("HTTP 401 — access token 만료. `claude`를 한 번 쓰면 갱신됩니다.")
        }
        fail("HTTP \(response.status): \(String(data: response.body, encoding: .utf8)?.prefix(300) ?? "")")
    }

    let usage: UsageResponse
    do {
        usage = try UsageResponse.parse(response.body)
    } catch {
        fail("응답 파싱 실패: \(error)")
    }

    let resetsDescription = usage.sevenDay.resetsAt.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown"
    print(String(
        format: "five_hour: %.1f%%   seven_day: %.1f%% (resets %@)\n",
        usage.fiveHour.utilization, usage.sevenDay.utilization, resetsDescription
    ))

    var accumulator = UsageAccumulator(state: StateStore.load(), calendar: .grass())
    accumulator.apply(utilization: usage.sevenDay.utilization, resetAt: usage.sevenDay.resetsAt, now: Date())
    do {
        try StateStore.save(accumulator.state)
    } catch {
        fail("상태 저장 실패: \(error)")
    }

    let daily = accumulator.state.daily
    if daily.isEmpty {
        print("첫 폴 = 베이스라인 설정 완료 (과거 백필 없음).")
        print("→ Claude를 좀 쓴 뒤 다시 실행하면 seven_day 증분이 일별로 쌓입니다.")
    } else {
        print("누적 일별 사용강도 (% of weekly limit) — 최근:")
        for key in daily.keys.sorted().suffix(14) {
            let value = daily[key] ?? 0
            let bar = String(repeating: "█", count: min(50, Int((value * 4).rounded())))
            print(String(format: "  %@  %6.2f%%  %@", key, value, bar))
        }
    }
    print("\nstate file: \(StateStore.fileURL.path)")
}
