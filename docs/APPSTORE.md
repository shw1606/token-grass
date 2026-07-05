# TokenGrass — 앱스토어 등록 계획 (App Store Submission Plan)

> **목표:** 무료 앱을 리젝 없이 한 번에 통과시키고, "비공식 토큰 사용" 특성 때문에 생길 수 있는 심사 리스크를 선제 제거.
> **상태:** Draft v0.1

---

## 0. 핵심 전제

- 무료 / IAP 없음 / 광고 없음 → 결제·구독 관련 가이드라인(3.x) 전부 회피.
- 백엔드·계정 없음 → 5.1.1(v) "계정 삭제" 의무의 가장 무거운 버전은 회피. 단, **토큰 삭제(연결 해제) 버튼은 반드시 제공**.
- 가장 큰 심사 리스크 두 가지: **(1) 2.1 완성도**(리뷰어가 토큰 없이 빈 화면을 봄), **(2) 5.1.1 프라이버시**(토큰=민감정보 취급).
- "private API" 우려는 오해 소지 있음 — Apple이 막는 건 *Apple 자체* 비공개 프레임워크. 외부 HTTPS 호출은 여기 해당 안 됨. (단, 메서드명이 Apple private selector와 우연히 겹치지 않게 주의.)
- **경쟁 인지:** 유사 앱 `Usage for Claude`가 이미 통과·운영 중(잔디는 앱 내부 전용·유료, 위젯엔 없음, Mac 필수). 즉 심사 통과 선례는 충분. 우리는 "위젯 잔디 / 폰 단독 / 무료"로 메타데이터·스샷에서 명확히 구분되게 표기한다. (상표·디스클레이머는 §3)

---

## 1. 사전 준비 체크리스트 (제출 전)

### 1.1 계정/등록
- [ ] Apple Developer Program 가입 ($99/년) — 개인 명의 vs 1인 사업자 명의 결정
- [ ] App Store Connect에서 앱 레코드 생성
- [ ] 번들 ID 확정 (예: `dev.yulebuilds.tokengrass`) + App Group ID (`group.dev.yulebuilds.tokengrass`)
- [ ] 인증서/프로비저닝 프로파일 (Xcode 자동 관리 권장)

### 1.2 필수 메타데이터
- [ ] 앱 이름 (30자) + 부제목 (30자)
- [ ] 프로모션 텍스트 (170자, 심사 없이 수정 가능 — 콘텐츠 업데이트용으로 활용)
- [ ] 설명 (4000자) — 기능 + **비공식 도구임을 명시** + 토큰 처리 방식
- [ ] 키워드 (100자): claude, token, usage, widget, heatmap, contribution, developer, ai, coding, grass ...
- [ ] **차별화 키워드를 부제목에 노출:** "Home screen contribution graph" / "Phone-only, free" 같은 표현으로 경쟁작과의 구분점을 검색·노출 단계에서부터 심기. 단, "Claude"는 부제목 주명칭으로 쓰지 않기(§3).
- [ ] 지원 URL (필수, 404/공사중 페이지면 즉시 리젝) → GitHub 레포 또는 seo-hnoo.me 서브페이지
- [ ] 마케팅 URL (선택)
- [ ] **개인정보 처리방침 URL (필수)** → PRIVACY.md를 호스팅 (GitHub Pages 또는 블로그)

### 1.3 스크린샷/미리보기
- [ ] 6.9" (또는 현 요구 최대 사이즈) iPhone 스크린샷 — **실제 앱 화면, 안드로이드/목업 프레임 금지**
- [ ] 홈스크린에 위젯이 올라간 실제 스샷 (핵심 셀링 포인트)
- [ ] 텍스트 오버레이는 영어 우선(글로벌) + 한국어 현지화 옵션
- [ ] (선택) 앱 미리보기 동영상: 토큰 붙여넣기 → 잔디 생성 15초

### 1.4 App Privacy "Nutrition Label" (App Store Connect 입력)
- 수집 데이터 신고. 우리 케이스 권장 신고:
  - **수집 안 함이 이상적.** 토큰·사용량이 전부 온디바이스고 우리 서버로 전송 안 하면 "Data Not Collected" 신고 가능.
  - 단, 제3자(=Anthropic) API를 직접 호출하므로 그 경계를 정확히: *우리(개발자)*가 수집/저장하지 않음을 기준으로 판단. 애매하면 보수적으로 "Diagnostics-아니오, 우리 서버 없음" 명시.
  - 크래시 리포팅 SDK(Firebase 등) **쓰지 않기** → 신고할 게 없어짐(심사·신뢰 모두 유리).

---

## 2. 가이드라인별 리스크 매핑 & 대응

| 가이드라인 | 리스크 | 대응 |
|---|---|---|
| **2.1 App Completeness** | 리뷰어가 토큰 없이 열면 빈 위젯/빈 화면 → 미완성 판정 | 토큰 없이도 **데모 잔디**가 보이게. 앱 내 "데모 모드" 명시. 플레이스홀더/Lorem ipsum 절대 금지 |
| **2.3 Accurate Metadata** | 과장 스샷, 기능 불일치 | 실제 화면만. "#1" 같은 표현 금지. 비공식임을 설명에 명시 |
| **2.5.1 Software Requirements (public API)** | 비공식 *Anthropic* API 사용 | Apple private API 아님 → 직접 해당 X. 단 설명에 "비공식, 변경 시 동작 보장 안 됨" 고지 |
| **4.0 Design / 미니멀 앱** | 위젯+설정만 → "너무 단순/웹페이지 래퍼" 의심 | 위젯이 핵심 가치임을 스샷·설명으로 강조. 웹뷰 래퍼 아님 |
| **5.1.1 Data Collection** | 토큰=민감 자격증명 처리 | 프라이버시 정책 명확. "토큰은 기기 Keychain에만, 우리 서버 전송 없음" 앱 내·정책 모두 명시 |
| **5.1.1(v) 계정 삭제** | 계정 시스템 없음 | 해당 약함. 그래도 **토큰 삭제 버튼** = 사용자 데이터 제거 경로 제공 |
| **5.2 지식재산권** | "Claude" 상표 사용 | 앱 이름에 "Claude" 단독 사용 자제. "for Claude Code"식 보조 표기는 통용되나, 아이콘/이름에 Anthropic 로고 미사용. 설명에 "Anthropic 비제휴/비승인" 디스클레이머 |
| **5.1.2 데이터 사용/공유** | 제3자 전송 오해 | 데이터 흐름 다이어그램을 정책에 포함 |

---

## 3. "Claude" 상표 & 비제휴 디스클레이머 (중요)

앱 이름·아이콘에 Anthropic 자산을 쓰면 5.2 리젝 위험. 안전 가이드:
- 앱 이름: Anthropic 상표를 주(主)명칭으로 쓰지 않기. (TokenGrass 같은 독립 브랜드 권장)
- 부제목/설명에서 호환성 설명은 가능: "Visualize your Claude Code token usage..."
- 설명 하단 고정 디스클레이머(영문 예):
  > TokenGrass is an independent, open-source project and is not affiliated with, endorsed by, or sponsored by Anthropic. "Claude" and "Claude Code" are trademarks of Anthropic.
- 아이콘에 Anthropic 로고/오렌지 별 모양 등 식별 자산 사용 금지.

---

## 4. 제출 → 심사 → 출시 플로우

1. **TestFlight 내부 테스트**: 실기기 다종(구형 SE, 노치/다이내믹 아일랜드, 다양한 iOS 버전)에서 위젯 3사이즈 + 온보딩 + 토큰 삭제 동작 확인.
2. **TestFlight 외부 테스트(선택)**: 개발자 커뮤니티 소수에게 베타 → 토큰 추출 마찰 실측, 피드백.
3. **App Store Connect 제출**: 메타데이터·스샷·프라이버시 라벨·정책 URL 완비.
4. **App Review 노트 작성(핵심)** — 리뷰어용 안내:
   - 데모 모드로 토큰 없이도 기능 확인 가능함을 명시.
   - (만약 실토큰 필요 시) 테스트용 자격증명 제공 방법 또는 데모 모드 경로 상세 기술.
   - 비공식 API 사용 사실과 온디바이스 저장 정책을 미리 설명 → 리뷰어 의문 선제 차단.
5. **심사 결과 대응**: 리젝 시 Resolution Center에서 근거 들어 회신(데모모드·정책 링크 첨부). 보통 메타데이터/완성도 이슈는 1–2회 핑퐁으로 해결.
6. **출시**: 수동 출시로 설정해 콘텐츠(Threads/LinkedIn) 발행과 타이밍 맞춤.

---

## 5. 앱스토어 설명 초안 (영문, 수정용 골격)

```
TokenGrass shows your daily Claude Code usage as a GitHub-style contribution
graph, right on your iPhone home screen. Just glance at the widget, no need to
open anything.

• The grass lives in the widget, in two sizes (2×2 and 4×2)
• A free Mac app collects your usage and syncs it over iCloud
• Everything stays on your devices. No account, no servers, nothing sent to us
• Free, with your full history. No paywall, no ads
• Open source (MIT)

How it works: install the free TokenGrass app on the Mac where you use Claude
Code. It reads your usage there and syncs a small summary to your iPhone over
iCloud. No login, no backend, and your Claude login never leaves your Mac.

You'll need the free Mac app (there's a download link inside) and Claude Code on
that Mac.

TokenGrass is an independent, open-source project. It isn't affiliated with,
endorsed by, or sponsored by Anthropic. "Claude" and "Claude Code" are trademarks
of Anthropic. It uses unofficial endpoints, so it may stop working if those
change.
```

### 5.1 App Review 노트 (App Store Connect "Notes" 칸에 그대로 붙여넣기)

```
TokenGrass visualizes the user's own Claude Code (developer CLI) usage as a
home-screen widget.

No login is required to review the app. Launched without the optional macOS
companion, the app and widget show clearly-labeled DEMO data, so all
functionality is fully reviewable on-device. To display real data, a free,
open-source macOS companion (download link shown in the app) reads the user's own
usage on their Mac and syncs a small summary through the user's private iCloud
(NSUbiquitousKeyValueStore).

- No account, no backend server; we collect no data (App Privacy: Data Not Collected).
- The iOS app makes no network calls of its own. It only reads a few KB from the
  user's own iCloud key-value store.
- Only Apple public frameworks are used (SwiftUI, WidgetKit); no private APIs.
- "Claude"/"Claude Code" are Anthropic trademarks. TokenGrass is an independent,
  unaffiliated open-source project (disclaimer shown in-app and in the listing).

Source code: https://github.com/shw1606/token-grass
```

한국어 현지화는 출시 후 프로모션 텍스트로 병행.

---

## 6. 비용 요약
- Apple Developer Program: **$99/년** (유일한 필수 비용)
- 백엔드/서버: **$0** (온디바이스)
- 도메인/호스팅: 기존 seo-hnoo.me 재활용 가능 → 추가 $0
- 총: **연 $99**

---

## 7. 출시 전 최종 게이트 (Definition of Done)
- [ ] Spike R1/R2 통과 (실데이터로 잔디가 실제로 그려짐)
- [ ] 토큰 없이 데모 잔디 렌더 확인
- [ ] 토큰 삭제 → Keychain에서 실제 제거 확인
- [ ] 위젯 3사이즈 실기기 렌더 확인 (메모리 크래시 없음)
- [ ] 프라이버시 정책 호스팅 + URL 연결
- [ ] App Review 노트 작성
- [ ] 디스클레이머 문구 앱 내 + 설명 양쪽 반영
- [ ] 오픈소스 레포 공개 + README
