# TokenGrass — 데이터 아키텍처 (v2, 실데이터)

> **상태:** 확정 초안 (구현 직전) · 2026-06-28
> **이 문서는 `DESIGN.md`의 §2(인증/토큰), §3(아키텍처), §6(온보딩 헬퍼)를 대체한다.** UI/위젯/색 매핑(§4~5)과 포지셔닝은 유효.
> **한 줄:** Mac 컴패니언이 Anthropic `/api/oauth/usage`를 주기적으로 폴링 → **한도 사용률(%)** 을 일별로 누적 → iCloud → iPhone 잔디 위젯. **백엔드/서버/DB 없음.**

---

## 0. 왜 이 구조인가 (리서치로 강제된 피벗)

설계 v1은 "폰이 직접 OAuth로 사용량을 받아 일별 토큰 잔디"를 가정했으나, 실측으로 셋 다 깨졌다:

1. **정책 위반.** Anthropic [Authentication and credential use](https://code.claude.com/docs/en/legal-and-compliance) (2026-02):
   *"OAuth는 구독 플랜 구매자의 Claude Code·native 앱 전용"*, *"제3자 개발자가 Claude.ai 로그인을 제공하거나 사용자 대신 Free/Pro/Max 자격증명으로 요청을 라우팅하는 것을 허용하지 않는다."* → **폰 앱이 직접 OAuth 호출 = 금지.** 앱스토어(Apple 5.2.1)에서도 리젝 사유.
2. **일별 토큰 히스토리가 없음.** `/api/oauth/usage`는 토큰 개수가 아니라 **한도 사용률(%)** 과 리셋 시각만 준다(§3). 일별 시계열 백필 불가.
3. **로컬 로그는 반쪽.** `~/.claude/projects/**/*.jsonl`은 *이 기기의 Claude Code(CLI)* 사용만 담는다 — claude.ai 챗·타 기기 누락, 보존 ~수주.

**해법(= 검증된 경쟁작 `Usage for Claude` 구조):** "회색" OAuth 호출을 **Mac 컴패니언**에 두고(사용자 자기 기기에서 자기 자격증명 사용), **iPhone 앱은 iCloud로 받은 결과만 표시**한다. 앱스토어 심사를 받는 iOS 앱은 자격증명·Anthropic 호출을 일절 안 하므로 깨끗하다. `/api/oauth/usage`의 `seven_day`는 **계정 전체**(모든 기기 + 챗) 사용을 합산하므로 "반쪽" 문제도 해결된다.

**받아들인 제약(확정):**
- 잔디 단위 = **"하루 사용 강도 = 한도의 %"** (토큰 개수 아님). 데이터가 그것뿐이고, Max 사용자에겐 더 의미 있는 지표.
- **과거 백필 없음.** 설치 시점부터 깨끗하게 앞으로 누적.
- **Mac 의존.** 경쟁작과 동일, 불가피.

---

## 1. 하이레벨 구조

```
┌──────────────── Mac (컴패니언) ─────────────────┐
│  백그라운드 폴러 (LaunchAgent / 로그인 메뉴바)      │
│   ├─ Keychain "Claude Code-credentials" 읽기      │
│   ├─ access token 만료 시 refresh                 │
│   ├─ GET /api/oauth/usage  (깰 때 + 1~3h 주기)    │
│   ├─ UsageAccumulator: seven_day% 차분 → 일별 누적 │
│   └─ 일별 요약 [date→intensity] 저장               │
│            │ write                                │
│            ▼                                       │
│      iCloud 컨테이너 (CloudKit private / KVS)      │  ← Apple이 동기화, 서버·비용 0
└────────────┼──────────────────────────────────────┘
             ▼ read
┌──────────── iPhone ────────────────────────────────┐
│  TokenGrass 앱  iCloud → App Group 로 미러          │
│            ▼                                         │
│  위젯 (2×2 / 4×2)  App Group 읽어 잔디 렌더           │  ← 차별점 (자격증명·네트워크 0)
└─────────────────────────────────────────────────────┘
```

iOS 앱/위젯은 **순수 표시 클라이언트** — 토큰·OAuth·Anthropic 호출 전무.

---

## 2. 인증 / 토큰 처리 (Mac 컴패니언 전용)

실측값:
- **Keychain:** 서비스 `Claude Code-credentials`, 계정 = 사용자명. 값 = `{"claudeAiOauth":{"accessToken","refreshToken","expiresAt"}}`.
- **usage:** `GET https://api.anthropic.com/api/oauth/usage`, 헤더 `Authorization: Bearer <access>`, `anthropic-beta: oauth-2025-04-20`.
- **refresh:** `POST https://platform.claude.com/v1/oauth/token` (또는 `console.anthropic.com/v1/oauth/token`), body `{"grant_type":"refresh_token","refresh_token":...,"client_id":"9d1c250a-e61b-44d9-88ed-5944d1962f5e"}`.
- access token ~8h 만료 → `expiresAt` 경과(또는 401) 시 refresh 먼저.

**온보딩:** 경쟁작처럼 "Claude Code로 연결" = 컴패니언이 Keychain에서 자동으로 읽음(브라우저 로그인 없음). refresh 회전 토큰도 그대로 보관.

> 주의: 컴패니언은 토큰을 **로컬에만** 둔다(어디에도 업로드 X). iCloud에는 **집계 결과만** 올라가고 토큰은 안 올라간다.

---

## 3. 데이터 소스: `/api/oauth/usage` (실측 응답)

```jsonc
{
  "five_hour":  { "utilization": 0.0,  "resets_at": "2026-06-27T22:00:00+00:00", "limit_dollars": null, "used_dollars": null },
  "seven_day":  { "utilization": 41.0, "resets_at": "2026-07-01T16:00:00+00:00", "limit_dollars": null },
  "seven_day_sonnet": { "utilization": 4.0, "resets_at": "2026-07-01T16:00:00+00:00" },
  "limits": [ { "kind":"session", "percent":0, ... }, { "kind":"weekly_all", "percent":41, "is_active":true }, ... ],
  "extra_usage": { "used_credits": 2661.0, "monthly_limit": 2300, "utilization": 100.0, "currency":"USD" },
  "spend": { "used": {"amount_minor":2661,"currency":"USD"}, ... }
}
```

핵심 판정:
- **토큰/달러 필드(`*_dollars`, 토큰 수) = 전부 null.** 사용량은 **정수 % (utilization)** 로만 노출.
- `five_hour` = 5시간 블록, `resets_at`에 리셋. `seven_day` = 주간, `resets_at`에 리셋.
- `resets_at`이 **고정 경계**라는 점은 두 창이 *리셋까지 누적되는 카운터*(롤링 아님)임을 강하게 시사. → **누적 차분 가능.** (확인: §5 스파이크)
- `extra_usage`/`spend`의 달러는 **추가구매 크레딧**(overage)일 뿐 기본 사용량과 무관 → 사용 안 함.

**우리가 쓰는 신호:** `seven_day.utilization` (주력), `five_hour.utilization` (보조/해상도 보강).

---

## 4. 잔디 지표 정의

- **하루 강도 `intensity[date]`** = 그날 발생한 `seven_day.utilization`의 증가분 (= 주간 한도의 몇 %를 그날 썼나).
- 색 5단계는 기존대로 **백분위 정규화**(`TokenGrassCore.LevelThresholds`) — 단위가 %라도 그대로 동작.
- 표시 문구: "token" → **"usage"** (또는 "활동")로. 위젯엔 텍스트 없음(현 디자인 유지).

**알려진 한계:** utilization이 **정수 %** 라 가벼운 날은 증가분이 0으로 떨어져 빈 칸이 될 수 있음(해상도 거침). 완화책: `five_hour` 피크도 병행 기록해 보조 신호로 사용(§5 오픈 항목).

---

## 5. 누적 알고리즘 (`UsageAccumulator`, 순수 로직 → 헤드리스 테스트)

**저장 상태**(iCloud + 로컬 미러):
```
daily:   [String(yyyy-MM-dd) : Double]     // 일별 강도(%) 누적
last:    { value: Double, at: Date, resetAt: Date }?   // 마지막 폴 스냅샷
```

**매 폴링** `apply(now, u = seven_day.utilization, resetAt)`:
```
if last == nil:
    last = {u, now, resetAt}           // 첫 폴 = 베이스라인. 과거 백필 안 함(깨끗한 시작).
    return

delta:
  if resetAt == last.resetAt:          // 같은 주간 창
      delta = max(0, u - last.value)   // 누적 차분 (음수면 0으로 클램프)
  else:                                // 주간 리셋이 사이에 발생
      delta = max(0, u)                // 새 창의 누적분만 계상(리셋 직전 미관측분은 소량 손실 허용)

// 갭 분배: [last.at, now] 사이의 날짜들에 delta를 분배 (확정: 균등)
days = calendarDays(from: last.at, to: now)
for d in days: daily[d] += delta / days.count

last = {u, now, resetAt}
```

**규칙/엣지:**
- **갭 분배(확정):** Mac이 3일 꺼졌다 켜지면 그 증가분을 3일에 **균등 분배**. (시간가중 분배는 v2 옵션.)
- **음수 클램프:** 같은 창에서 값이 줄면(이상치) 0.
- **주간 리셋 교차:** 리셋 직전 최종값을 못 봤으면 그 미관측 꼬리만 소량 손실 — 총량 영향 미미.
- **윈도 보존 731일:** `daily`에서 오래된(>~53주) 항목 정리.
- 이 함수는 `Date`/난수 없이 인자로만 동작 → **단위테스트 100%.**

---

## 6. 폴링 & "Mac 항상 안 켜짐" 복원력

- **Mac 24h 상주 불필요.** `seven_day`는 **서버 누적 상태**라, Mac이 꺼져 있던 동안의 사용도 **다음 폴 한 번에 반영**됨.
- **요구 최소치:** *주간 리셋 1회당 최소 1번* 폴 → 그래야 그 주가 통째로 유실되지 않음. 즉 "일주일에 한 번은 Mac 켜기".

| Mac 가동 | 결과 |
|---|---|
| 매일 1회+ | 일별 정확 |
| 며칠 꺼짐 후 폴 | 총량 보존, 그 구간만 **균등 분배**(모양 근사) |
| 주간 전체 꺼짐(리셋 넘김) | 그 주 유실 |

**구현:** macOS **LaunchAgent**(또는 로그인 항목 메뉴바 앱) — GUI 안 띄워도 동작. 트리거: 로그인 + **wake-from-sleep 즉시** + 1~3h 타이머. 네트워크 실패/401 시 백오프 후 다음 주기.

---

## 7. 동기화: iCloud (백엔드/DB 없음)

- 동기화 대상 = `daily` 요약(1년 ≈ 365개 Double) + `last` → **수 KB**.
- **옵션 A (권장 시작):** `NSUbiquitousKeyValueStore`(iCloud KVS, 1MB 한도) — 단일 JSON blob. 가장 단순. Mac↔iOS가 동일 iCloud 컨테이너 공유.
- **옵션 B:** CloudKit private DB 레코드 1개 — 더 견고, 충돌처리. 데이터 커지면 전환.
- iOS 앱은 iCloud에서 읽어 **App Group**(`group.dev.yulebuilds.tokengrass`)에 미러 → 위젯이 App Group만 읽음(현행 그대로).
- **서버·DB·계정·비용 = 0.** 각 사용자 자기 iCloud 안에서만.

---

## 8. 컴포넌트 / 타깃

| 타깃 | 역할 | 신규? |
|---|---|---|
| `TokenGrassCore` (SPM) | 모델·색단계·날짜그리드·**`UsageAccumulator`**·`UsageClient` 파싱(순수)·데모 | 확장 |
| `TokenGrassMac` (macOS 앱) | 메뉴바 + LaunchAgent 폴러 + Keychain/refresh + iCloud write + 앱내 잔디 | **신규** |
| `TokenGrass` (iOS 앱) | iCloud→App Group 미러 + 화면 | 수정 |
| `TokenGrassWidget` | 잔디 렌더 | 현행 |
| `SharedUI` | 잔디 뷰(앱·위젯·Mac 공유 가능) | 현행 |

순수 로직(`UsageAccumulator`, 응답 파서, 차분/분배)은 전부 `TokenGrassCore`에 → `swift test`로 검증.

---

## 9. 컴플라이언스 & 앱스토어 포지션

- **iOS 앱**: 자격증명·OAuth·Anthropic 호출 **전무**, iCloud 표시만 → 심사상 깨끗(검증된 경쟁작과 동일 구조).
- **Mac 앱**: 사용자가 자기 기기에서 자기 토큰으로 자기 사용량 조회(회색지대지만 경쟁작이 통과한 동일 패턴). Claude **로그인 UI 제공 안 함**(Keychain 자동 읽기) → "third-party Claude login" 금지 조항 회피.
- 메타/설명에 **비공식·비제휴 디스클레이머** 유지(APPSTORE §3). 비공식 엔드포인트라 **언제든 깨질 수 있음** 고지.
- 차별점 = **홈 위젯 잔디**(경쟁작은 게이지 위젯만) + 오픈소스.

---

## 10. 프라이버시
- 토큰: Mac **Keychain만**, 업로드 0.
- iCloud: 집계 강도 요약만(대화·토큰 원문 없음), 사용자 개인 iCloud.
- 우리 서버 없음 → "Data Not Collected" 신고 가능.

---

## 11. 오픈 검증 / 스파이크 (구현 중 확정)
- [x] **S1 — `seven_day` 누적형 확인됨:** 2회 폴링 **41% → 43%** (동일 `resets_at` 16:00, 마이크로초만 jitter), `five_hour` 0→6. 누적-단조 확정 → §5 차분 채택. **윈도 동일성은 `resets_at` ±120초 허용 비교**(마이크로초 jitter 때문). 파서+`UsageAccumulator`+테스트 구현·통과(28/28).
- [ ] **S2 — refresh 동작:** `platform.claude.com/v1/oauth/token`로 access 갱신 PoC(Cloudflare 차단 여부).
- [ ] **S3 — 해상도:** 정수 % 가 가벼운 날을 0으로 만드는 정도 측정 → `five_hour` 병행 필요성 결정.
- [ ] **S4 — iCloud:** Mac↔iOS KVS/CloudKit 동기화 + entitlement(유료 계정).
- [ ] **S5 — 멀티 기기:** 한 계정 여러 Mac에 컴패니언 시 중복 가산 방지(같은 `seven_day`를 두 Mac이 차분하면 이중계상) → "리더 1대" 또는 iCloud 머지 규칙.

---

## 12. 리스크
- **R1 비공식 엔드포인트** — 스키마/정책 변경 시 중단. → 파서 느슨, 실패 시 graceful.
- **R2 정책 강화** — Anthropic이 무통보 차단 가능. → 오픈소스/비공식 명시, 폴링 보수적(1~3h).
- **R3 멀티 Mac 이중계상**(S5).
- **R4 정수 % 해상도**(S3).
- **R5 Mac 의존** — 수용됨.

---

## 13. 빌드 순서
1. `TokenGrassCore`: `UsageResponse` 파서 + `UsageAccumulator`(차분·갭분배·리셋) + 테스트.
2. macOS 컴패니언 골격: Keychain 읽기 + usage 폴 1회 + 콘솔 출력(실데이터 누적 확인).
3. refresh(S2) + LaunchAgent 폴러 + 로컬 영속화.
4. iCloud write(KVS) → iOS read → App Group → 위젯 실데이터.
5. Mac 앱 UI(메뉴바 + 앱내 잔디) + 온보딩.
6. 멀티기기(S5)·해상도(S3) 마감 → TestFlight.
