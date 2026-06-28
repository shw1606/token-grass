import Foundation
import TokenGrassCore

/// Validates the in-app "Sign in with Claude" flow end to end:
/// authorize URL → user logs in & pastes the code → token exchange → usage poll.
/// This is exactly what the macOS app will do (just without a GUI).
func runLogin() {
    let pkce = PKCE.random()
    let state = OAuthFlow.randomState()
    let authorizeURL = OAuthFlow.authorizeURL(pkce: pkce, state: state)

    print("""

    === TokenGrass · Sign in with Claude (검증) ===

    1) 아래 URL이 브라우저에서 열립니다. Claude 로그인 → 승인하세요.
       (안 열리면 직접 복사해서 여세요)

    \(authorizeURL.absoluteString)
    """)
    openURL(authorizeURL)

    print("""

    2) 승인 후 페이지에 표시되는 '코드'를 복사해서 붙여넣고 Enter:
    """)
    print("코드> ", terminator: "")
    guard let line = readLine(), !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        fail("코드 입력이 없습니다.")
    }
    let parsed = OAuthFlow.parsePastedCode(line)

    print("\n토큰 교환 중… (platform.claude.com/v1/oauth/token)")
    let tokens: OAuthTokens
    do {
        tokens = try OAuthClient.exchange(code: parsed.code, verifier: pkce.verifier, state: parsed.state ?? state)
    } catch {
        fail("토큰 교환 실패: \(error)\n  (이게 Cloudflare에 막히면 R2 — 알려주세요.)")
    }

    do { try TokenStore.save(tokens) } catch { fail("토큰 저장 실패: \(error)") }
    print("✓ 로그인 성공!  만료: \(ISO8601DateFormatter().string(from: tokens.expiresAt))  scope: \(tokens.scope ?? "-")")
    print("  저장: \(TokenStore.fileURL.path)")

    print("\n3) 검증: 방금 발급된 토큰으로 usage 폴…")
    do {
        let response = try UsageAPI.fetchUsage(accessToken: tokens.accessToken)
        guard response.status == 200 else {
            fail("usage HTTP \(response.status): \(String(data: response.body, encoding: .utf8)?.prefix(200) ?? "")")
        }
        let usage = try UsageResponse.parse(response.body)
        print(String(format: "✓ five_hour: %.1f%%   seven_day: %.1f%%", usage.fiveHour.utilization, usage.sevenDay.utilization))
        print("\n🎉 인앱 로그인 → 토큰 교환 → usage 전 구간 동작 확인. 이 흐름을 macOS 앱으로 감싸면 됩니다.")
    } catch {
        fail("usage 검증 실패: \(error)")
    }
}
