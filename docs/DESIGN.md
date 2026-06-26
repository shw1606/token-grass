# TokenGrass — 설계 문서 (Design Doc)

> Claude Code 토큰 사용량을 GitHub 컨트리뷰션 잔디밭 스타일로 보여주는 iOS 홈스크린 위젯
> **상태:** Draft v0.1 · **작성:** @yulebuilds · **라이선스 방향:** MIT (오픈소스)

---

## 0. 한 줄 요약

**Mac 없이, iPhone 홈스크린에, 잔디밭만. 무료 · 오픈소스 · 페이월 제로.**

iPhone 홈스크린에 "내 Claude 잔디밭"을 띄운다. Claude Code OAuth refresh token을 한 번 붙여넣으면, 앱이 주기적으로 Anthropic usage 데이터를 받아 일별 토큰 사용량을 GitHub식 히트맵으로 그린다. 데이터 수집을 위한 Mac 컴패니언이 필요 없고(폰 단독), 잔디밭이 앱 안이 아니라 **홈스크린 위젯**에 바로 뜨며, 어떤 기능에도 페이월이 없다.

> **포지셔닝 근거 (실측):** 가장 가까운 경쟁자 `Usage for Claude`는 (1) 잔디밭이 앱 내부에만 있고 홈스크린 위젯엔 없으며, (2) 데이터 수집에 Mac 컴패니언이 필수이고, (3) 풀 히스토리/고급 기능이 유료(IAP). 우리는 이 세 칸을 정확히 비워둔 자리를 노린다. (경쟁 분석 §1.3)

---

## 1. 목표와 비목표 (Goals / Non-Goals)

### 1.1 목표
- iOS 홈스크린 위젯(소/중/대)에 52주 × 7일 컨트리뷰션 히트맵 렌더링 — **잔디밭을 위젯에서 바로** (앱 진입 불필요)
- 일별 토큰 사용량을 GitHub 잔디 4~5단계 강도로 색 매핑
- 최소 설정 화면: 토큰 1개 붙여넣기 → 연결 → 끝 — **Mac 컴패니언 불필요(폰 단독)**
- 100% 온디바이스 저장 (토큰·사용량 데이터 서버 전송 없음)
- 모든 기능 무료, 페이월/IAP 없음
- 오픈소스로 공개해 빌더 콘텐츠로 활용

### 1.1.1 차별화 3대 기둥 (경쟁 대비)
1. **위젯 네이티브 잔디밭** — 경쟁작은 잔디를 앱 안에 가둔다. 우리는 홈스크린 위젯이 1급 시민.
2. **폰 단독(Mac-free)** — 경쟁작은 Mac 컴패니언이 데이터 수집의 심장. 우리는 폰이 직접 토큰으로 호출(A안) → Mac/노트북 없는 사용자의 유일한 선택지.
3. **무료·오픈소스·페이월 제로** — 경쟁작은 풀 히스토리/고급 기능이 유료. 우리는 잔디 전체 기간 무료.

### 1.2 비목표 (이번 MVP에서 안 함)
- 멀티 플랫폼 합산 (OpenClaw, Codex, Cursor 등) — v2 후보
- 리더보드 / 소셜 공유 기능 — v2 후보
- 정교한 비용($) 추정 — v2 후보
- Android — 별도 트랙
- Apple Watch / Mac 위젯 — v2 후보
- 자체 백엔드 / 계정 시스템 — A안 채택으로 불필요

### 1.3 경쟁 분석 (실측 기반)

#### 1.3.1 직접 경쟁자: `Usage for Claude` (amir hayek)
실제 설치하여 확인한 사실:
- 잔디밭(GitHub식 액티비티 그리드) 기능이 **있다. 단, 앱 안으로 들어가야만 보인다 — 홈스크린 위젯엔 잔디밭이 없다.**
- 홈스크린/락스크린 위젯은 한도 게이지(링/컴팩트/바) 위주.
- 데이터 수집에 **Mac 컴패니언 앱이 필수** (iOS는 iCloud로 동기화만).
- 풀 히스토리/고급 기능이 **유료**(IAP: Dashboard Full History $14.99, Monthly Pro $4.99 등).
- 완성도 높고 전 기기 지원(Mac/iPhone/iPad/Watch/Vision), 15개 언어, 활발한 업데이트.

→ **우리와 정면으로 겹치지 않는다.** 그들이 비운 정확한 세 칸(위젯 잔디 / 폰 단독 / 무료)이 우리 자리.

#### 1.3.2 기타 관련 구현 (대부분 데스크탑/웹, 위젯 잔디 아님)
| 도구 | 형태 | 잔디 | iPhone 홈위젯 | 비고 |
|---|---|---|---|---|
| Usage for Claude | iOS+Mac 앱 | 앱 내 O | ✗ (게이지만) | Mac 필수, 유료 IAP |
| claude-stats (1pitaph) | macOS+iOS 컴패니언 | 대시보드 O | ✗ | 소스 빌드만, 앱스토어 X |
| claude-usage-widget (ankurkakroo2) | macOS 메뉴바+위젯 | — | ✗ | 일시정지·미완성 |
| claude-usage-widget (bozdemir) | 데스크탑 위젯 | 90일/52주 O | ✗ | 데스크탑 전용 |
| Tilo Mitra 블로그 위젯 | 웹 컴포넌트 | O | ✗ | 개인 홈페이지용 |
| tokscale (junhoyeo) | CLI+웹 | 2D/3D O | ✗ | 모바일 토큰전송(QR) 포석 있음 |
| cc-heatmap (yurukusa) | npx → HTML | O | ✗ | standalone HTML |

#### 1.3.3 결론
- "잔디밭" 패턴 자체는 데스크탑/웹에 흔하다. **하지만 'iPhone 홈스크린 위젯에 잔디밭'이라는 정확한 조합은 비어 있다.**
- 시장이 통째로 빈 게 아니라 **이 특정 교집합(위젯 잔디 ∩ 폰 단독 ∩ 무료)이 비어 있어** 유효하다.
- 수요는 검증됨: 경쟁작 리뷰에서 "Anthropic이 이 기능을 안 낸 게 놀랍다", "한도 관리에 큰 도움" 등 강한 니즈가 확인됨.
- ⚠️ 리스크: `Usage for Claude` 개발자가 빠르게 움직임 → 위젯 잔디를 추가할 수 있음. **속도가 곧 해자.** 빨리 내고 오픈소스로 선점.

---

## 2. 핵심 제약 (이 설계를 강제하는 사실들)

### 2.1 WidgetKit 런타임 제약
- **위젯은 백그라운드 실행 불가.** URLSession·원격 쿼리를 위젯에서 직접 못 돌린다. 데이터는 타임라인 갱신 *전에* 미리 받아 가공돼 있어야 한다.
- **메모리 ~30MB.** 초과 시 즉시 Jetsam(크래시). → 이미지 대신 SwiftUI 벡터 셀(RoundedRectangle)로 그려 회피.
- **리프레시 예산 하루 ~40–70회 (15–60분 간격).** 잔디밭은 하루 단위 데이터라 영향 없음. 자정 1회 갱신이면 충분.
- 데이터 공유는 App Group(`UserDefaults(suiteName:)` 또는 파일)로.

### 2.2 인증/토큰 제약 (가장 중요)
- Claude Code 토큰은 macOS는 **Keychain**, Linux는 `~/.claude/.credentials.json`(권한 600)에 저장. 형태:
  ```json
  { "claudeAiOauth": { "accessToken": "sk-ant-oat01-...", "refreshToken": "...", "expiresAt": "<ISO8601>" } }
  ```
- **access token은 약 8시간 후 만료**, refresh token으로 새 access token 무기한 발급 가능.
- ⚠️ **알려진 위험:** OAuth refresh 엔드포인트가 Cloudflare로 보호되어 CLI 외부에서 직접 호출 시 실패 사례가 보고됨(claude-code #44945). → 폰 앱에서 refresh가 막힐 가능성을 반드시 검증해야 함. (§7 리스크 참조)
- usage 데이터를 주는 엔드포인트는 **비공식·비문서화**. 언제든 바뀌거나 막힐 수 있음.

### 2.3 비공식성 = 제품의 근본 리스크
- 이 앱은 Anthropic 비승인 방식. 플랫폼 의존도가 높고 기술 moat가 약함.
- → 그래서 "수익 제품"이 아니라 **오픈소스 빌더 콘텐츠**로 포지셔닝. 깨져도 콘텐츠 가치는 남는다.
- 차별화도 기능 해자가 아니라 **포지션 해자**(위젯 잔디 ∩ 폰 단독 ∩ 무료)에서 나온다. §1.3 참조. 따라서 "세계 최초" 톤은 쓰지 않고, "이미 있는 걸 내 방식으로 더 미니멀하게, Mac 없이, 무료로 다시 만든 기록"으로 서사화한다.

---

## 3. 아키텍처

### 3.1 컴포넌트 다이어그램
```
+-------------------------- iPhone --------------------------+
|                                                            |
|  +--------------+      App Group        +--------------+   |
|  | Main App     |  (UserDefaults suite  |  Widget      |   |
|  | (SwiftUI)    |   + shared container) |  Extension   |   |
|  |              | --------------------> |  (WidgetKit) |   |
|  | - 토큰 입력/저장|   [date:tokenCount]    |              |   |
|  | - 사용량 폴링  |                       | - 잔디 렌더    |   |
|  | - 집계/캐싱   | <-------------------- | - 타임라인     |   |
|  +------+-------+   reloadTimelines()   +--------------+   |
|         |                                                  |
|  토큰: Keychain(Main app), 평문 저장 안 함                      |
+---------+--------------------------------------------------+
          | HTTPS (Bearer access token)
          v
   api.anthropic.com  (비공식 usage 엔드포인트)
   + OAuth refresh 엔드포인트 (Cloudflare 보호 — 검증 필요)
```

### 3.2 데이터 흐름
1. **온보딩:** 사용자가 Mac/Linux에서 헬퍼 스크립트로 `~/.claude/.credentials.json`(또는 Keychain) 값을 추출 → 앱에 붙여넣기.
2. **저장:** 앱이 access/refresh token + expiresAt을 iOS **Keychain**에 저장 (UserDefaults 아님).
3. **폴링:** 메인 앱이 포그라운드 진입 시 + `BGAppRefreshTask`(가능 시 ~30–60분)로 usage 조회.
   - access token 만료(`expiresAt` 경과)면 refresh 먼저 시도.
4. **집계:** 응답을 `[yyyy-MM-dd: tokenCount]` 딕셔너리로 정규화 → App Group에 저장.
5. **렌더 트리거:** `WidgetCenter.shared.reloadAllTimelines()` 호출.
6. **위젯:** TimelineProvider가 App Group에서 읽어 잔디 그리드 렌더. 네트워크 호출 없음. 다음 자정에 1 entry 갱신(`.after`).

### 3.3 왜 이 구조인가
- 위젯이 네트워크를 못 쓰므로, **메인 앱이 데이터 공급자**, 위젯은 **순수 렌더러**로 역할 분리.
- 토큰은 Keychain, 사용량 캐시는 App Group — 민감도에 따라 저장소 분리.
- 백엔드/계정 없음 → 프라이버시 단순(=앱스토어 심사 유리), 운영 비용 0.

---

## 4. 데이터 모델

### 4.1 토큰 자격증명 (Keychain 저장)
```swift
struct ClaudeCredential: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}
```

### 4.2 일별 사용량 (App Group 저장)
```swift
struct DailyUsage: Codable {
    let date: String        // "2026-06-26" (로컬 타임존 기준 자정 경계)
    let totalTokens: Int    // input + output 합 (MVP는 단순 합)
}

struct UsageSnapshot: Codable {
    let days: [DailyUsage]      // 최근 ~371일 (53주)
    let lastUpdated: Date
    let maxTokensInWindow: Int  // 색 강도 정규화용
}
```

### 4.3 색 강도 매핑 (GitHub식 5단계)
```
level 0: tokens == 0            -> 빈 셀 (배경)
level 1: 0 < t <= p25
level 2: p25 < t <= p50
level 3: p50 < t <= p75
level 4: t > p75
```
- 정규화는 **백분위 기반**(절대값 아님). 사용량 편차가 커도 잔디가 예쁘게 분포.
- 색상: GitHub green 기본 + 테마 옵션(Claude 오렌지) — 설정에서 토글(v1.1).

---

## 5. 화면/위젯 스펙

### 5.1 메인 앱 (MVP — 단일 화면)
- **연결 안 됨 상태:** 안내 + "토큰 붙여넣기" 텍스트필드 + [연결] 버튼 + 헬퍼 스크립트 복사 버튼 + 도움말 링크.
- **연결됨 상태:** 미니 잔디 미리보기 + 마지막 동기화 시각 + [지금 동기화] + [연결 해제(토큰 삭제)] 버튼.
- 데모 데이터: 토큰 없이 앱을 열어도(=리뷰어) 가짜 잔디가 보이게. "DEMO" 워터마크 표기.

### 5.2 위젯 패밀리
| 패밀리 | 내용 |
|---|---|
| `systemSmall` | 최근 ~17주 압축 잔디 + 오늘 토큰 수 |
| `systemMedium` | 최근 ~30주 잔디 + 주간 합계 |
| `systemLarge` | 전체 53주 잔디 + 월 레이블 + 총합 |
| (옵션) `accessoryRectangular` | 락스크린용 미니 스트릭 |

### 5.3 위젯 뷰 핵심 (SwiftUI 스케치)
```swift
// 셀 그리드 — 이미지 X, 벡터 O (메모리 안전)
LazyHGrid(rows: Array(repeating: GridItem(.fixed(cell), spacing: gap), count: 7)) {
    ForEach(entry.snapshot.days, id: \.date) { day in
        RoundedRectangle(cornerRadius: 2)
            .fill(color(for: level(day.totalTokens)))
            .frame(width: cell, height: cell)
    }
}
```

---

## 6. 헬퍼 스크립트 (토큰 추출 — 온보딩 핵심)

사용자 마찰의 핵심 지점. 한 줄 복붙으로 끝나게 만든다.

### 6.1 macOS (Keychain)
```bash
# Claude Code 자격증명을 Keychain에서 읽어 한 줄 JSON으로 출력
security find-generic-password -s "Claude Code" -w 2>/dev/null \
  || echo "Claude Code 자격증명을 찾지 못했습니다. 먼저 'claude' 로그인 필요."
```
> 주: 실제 서비스명/계정명은 디바이스에서 검증 필요(§7). `claude setup-token`으로 1년짜리 장기 토큰을 만들어 붙여넣는 우회도 제공.

### 6.2 Linux / 원격 서버
```bash
cat ~/.claude/.credentials.json | tr -d '\n'
```

### 6.3 더 안전한 대안 (권장 표기)
- `claude setup-token`으로 발급한 **장기 OAuth 토큰**을 붙여넣게 안내.
  - 장점: refresh 로직 불필요(만료 길다), Cloudflare refresh 위험 회피.
  - 단점: 사용자가 명령 1회 실행 필요 — 그래도 mitmproxy류보다 압도적으로 간단.

---

## 7. 리스크 & 검증 항목 (Spike 필요)

| # | 리스크 | 영향 | 검증 방법 | 대응 |
|---|---|---|---|---|
| R1 | usage 엔드포인트가 비공식 → 응답 스키마 불명/변경 | 치명 | 실토큰으로 실제 응답 캡처, 스키마 고정 | 파서를 느슨하게, 실패 시 graceful degrade |
| R2 | refresh 엔드포인트 Cloudflare 차단 (#44945) | 높음 | 폰/앱에서 refresh 호출 PoC | 차단 시 `setup-token` 장기토큰만 지원 |
| R3 | Anthropic ToS/차단 (바이럴로 트래픽↑ 시) | 높음 | ToS 재확인, 호출 빈도 최소화 | 비공식 명시, 캐싱 공격적, 폴링 보수적 |
| R4 | 토큰 탈취 우려 (사용자 신뢰) | 중 | 보안 설계 공개(오픈소스) | Keychain만, 평문/전송 0, 코드 공개 |
| R5 | 앱스토어 리젝 (2.1 완성도/5.1.1 프라이버시) | 중 | TestFlight·가이드라인 점검 | 데모데이터·프라이버시 정책·토큰삭제 버튼 |
| R6 | "데이터가 없다"는 신규 사용자 빈 위젯 | 낮 | — | 첫 동기화 전 데모/플레이스홀더 |

**MVP 착수 전 반드시 끝낼 Spike 2개:** R1(실응답 캡처) + R2(refresh 가능여부). 이 둘 결과로 토큰 전략(refresh vs setup-token 전용)이 갈린다.

---

## 8. 기술 스택

- **언어/UI:** Swift, SwiftUI, WidgetKit
- **백그라운드:** BackgroundTasks (`BGAppRefreshTask`)
- **저장:** Keychain Services(토큰) + App Group UserDefaults/파일(사용량 캐시)
- **네트워킹:** URLSession (메인 앱 전용)
- **최소 타깃:** iOS 17+ (WidgetKit 성숙도/`containerBackground` 등 고려)
- **의존성:** 없음(외부 SDK 0) — 프라이버시·심사·신뢰 모두 유리
- **배포:** App Store + GitHub 오픈소스(MIT)

---

## 9. 디렉토리 구조 (예정)
```
token-grass/
├─ TokenGrass/                 # 메인 앱 타깃
│  ├─ TokenGrassApp.swift
│  ├─ Views/ (Onboarding, Connected, Demo)
│  ├─ Services/ (KeychainStore, UsageClient, UsageAggregator, TokenRefresher)
│  └─ Shared/ (models, AppGroup helpers, color mapping)  ← 위젯과 공유
├─ TokenGrassWidget/           # 위젯 익스텐션 타깃
│  ├─ TokenGrassWidget.swift   # @main Widget
│  ├─ Provider.swift        # TimelineProvider
│  └─ GrassView.swift       # 잔디 렌더
├─ scripts/
│  └─ extract-token.sh      # 온보딩 헬퍼
├─ README.md                # 오픈소스 진입점 (콘텐츠 허브)
├─ PRIVACY.md               # 프라이버시 정책 (앱스토어 링크)
└─ LICENSE                  # MIT
```

---

## 10. 열린 결정 사항
- [ ] 최종 앱 이름/번들 ID (네이밍 ROADMAP 참조)
- [ ] iOS 최소 버전 17 vs 18
- [ ] 색 테마 기본값: GitHub green vs Claude orange
- [ ] 토큰 전략: refresh 지원 vs setup-token 전용 (R2 결과에 따라)
- [ ] 위젯에 "오늘/주간/총" 중 무엇을 숫자로 노출할지
