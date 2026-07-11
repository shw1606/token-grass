import Foundation
import SwiftUI
import AppKit
import TokenGrassCore

/// Not signed in with the app's own account yet — no token to poll with.
struct NotSignedIn: Error {}
/// The app's own refresh token is dead; the user must sign in again.
struct StandaloneAuthExpired: Error {}

/// Signs in with the user's own Claude account, self-refreshes its token,
/// polls usage, accumulates daily intensity, and publishes the grass + status.
@MainActor
final class UsageService: ObservableObject {
    enum Connection: Equatable {
        case unknown, notConnected, ok, error(String)
        /// The token/refresh is dead — the fix is "sign in again", not "wait and
        /// retry". The UI offers an in-app re-login (Settings → 계정).
        case authExpired(String)
    }

    @Published private(set) var connection: Connection = .unknown
    @Published private(set) var fiveHour: Double = 0
    @Published private(set) var sevenDay: Double = 0
    @Published private(set) var fiveHourResetsAt: Date?
    @Published private(set) var sevenDayResetsAt: Date?
    @Published private(set) var lastSync: Date?
    @Published private(set) var grid: GrassGrid = DateGrid.makeGrid(usage: [:], weeks: 26)
    /// True while a sync is in flight AND for a short cooldown afterward — the
    /// UI disables its sync buttons on this so a human mashing "지금 동기화"
    /// can't fire a burst of requests into a real rate limit.
    @Published private(set) var isBusy = false

    private var accumulator: UsageAccumulator
    private var timer: Timer?
    /// Held for the app's lifetime to opt out of App Nap. As a menu-bar-only
    /// (LSUIElement) app with no window, macOS can throttle our background
    /// 5-min Timer heavily once napped — a transient sync error can then sit
    /// unrefreshed far longer than intended. `.userInitiatedAllowingIdleSystemSleep`
    /// only disables App Nap for this process; it does NOT keep the Mac itself
    /// awake (unlike `caffeinate`), so normal sleep/wake behavior is unaffected.
    private var activityToken: NSObjectProtocol?

    init() {
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Keep syncing Claude usage on schedule"
        )
        accumulator = UsageAccumulator(state: MacStateStore.load(), calendar: .grass())
        // Restore from iCloud so a fresh install (or a brand-new Mac) picks up the
        // existing grass instead of starting blank. Merge keeps the larger value
        // per day, so a reinstall never loses what's already recorded.
        NSUbiquitousKeyValueStore.default.synchronize()
        if let cloud = ICloudGrassStore.read()?.daily { accumulator.mergeDaily(cloud) }
        refreshGrid()
        SyncLog.log("=== app launch (build \(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "?")) ===")
        // The first sync() call schedules its own recurring timer when it
        // completes (see scheduleNextPoll) — no separate fixed-interval Timer
        // needed here.
        #if DEBUG
        seedFakeStandaloneTokenIfAsked()
        #endif
        Task { await sync() }
        // Catch up on wake from sleep (the poll timer doesn't fire while
        // asleep). Wait a few seconds first so networking is back up — a poll
        // fired the instant we wake often hits a dead connection and returns
        // an empty 200.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            SyncLog.log("system woke from sleep")
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await self?.sync()
            }
        }
        // iCloud KVS downloads in the background; merge late-arriving data so a
        // fresh install restores its history even if it wasn't ready at launch.
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.restoreFromICloud() }
        }
    }

    /// Merge grass that arrived from iCloud (e.g. after a fresh install) into the
    /// local accumulator, so history is restored rather than overwritten.
    private func restoreFromICloud() {
        guard let cloud = ICloudGrassStore.read()?.daily, !cloud.isEmpty else { return }
        if accumulator.mergeDaily(cloud) {
            MacStateStore.save(accumulator.state)
            refreshGrid()
        }
    }

    var hasData: Bool { !accumulator.state.daily.isEmpty }

    /// Push to iCloud once per launch even if nothing changed, so a freshly
    /// installed iPhone/widget gets the current grass immediately.
    private var hasPushedICloud = false

    /// Guards against BOTH true overlap (the 5-min timer, the wake handler, and
    /// a manual tap landing within moments of each other) AND a human mashing
    /// "지금 동기화" many times in a row — a real user did exactly that and
    /// turned it into a cascade of 429s, since each quick request completed
    /// before the next tap, so a simple "already in flight" guard never
    /// tripped. `minInterval` enforces a floor between network attempts no
    /// matter how many times the button is pressed; `staleLockTimeout` is a
    /// safety net so a sync that somehow never completes can't wedge every
    /// future attempt forever.
    private var lastAttemptAt: Date?
    private let minInterval: TimeInterval = 10
    private let staleLockTimeout: TimeInterval = 45

    /// Consecutive failures drive exponential backoff on the recurring poll
    /// (see scheduleNextPoll) — a sustained outage (expired session, sustained
    /// rate limit) must NOT be retried every 5 minutes forever. A real incident
    /// showed exactly that: repeated 401s escalated into a 429 rate-limit that
    /// then persisted for 35+ minutes while we kept polling on the fixed
    /// interval regardless, which likely prolonged it.
    private var consecutiveFailures = 0
    private let basePollInterval: TimeInterval = 5 * 60
    private let maxPollInterval: TimeInterval = 60 * 60

    func sync() async {
        let now = Date()
        if isBusy, let last = lastAttemptAt {
            let elapsed = now.timeIntervalSince(last)
            if elapsed < staleLockTimeout {
                SyncLog.log("sync() dropped — busy/cooling down (\(String(format: "%.1f", elapsed))s)")
                return
            }
            SyncLog.log("⚠️ previous sync stuck for \(Int(elapsed))s — forcing through anyway")
        }
        lastAttemptAt = now
        isBusy = true
        defer { isBusy = false }

        SyncLog.log("sync() start (signedIn=\(isStandalone))")
        do {
            let usage = try await fetchUsageRefreshingTokenIfNeeded()
            applyUsage(usage)
            lastSync = Date()
            connection = .ok
            consecutiveFailures = 0
            SyncLog.log("sync() OK 5h=\(usage.fiveHour.utilization) 7d=\(usage.sevenDay.utilization)")
        } catch is NotSignedIn {
            connection = .notConnected
            SyncLog.log("sync() — not signed in")
        } catch {
            connection = Self.connectionState(for: error)
            consecutiveFailures += 1
            SyncLog.log("sync() FAILED — \(error) (consecutiveFailures=\(consecutiveFailures))")
        }
        // Every sync (whether from the timer, wake, or a manual tap) reschedules
        // the next automatic poll — a successful manual retry during an outage
        // immediately restores the normal 5-min cadence instead of waiting out
        // whatever backoff was already in flight.
        scheduleNextPoll()

        // Keep the button disabled a little past the network round-trip so a
        // fast success/failure still leaves at least `minInterval` between
        // attempts — a human mashing the button gets one request, not a burst.
        let coolMore = minInterval - Date().timeIntervalSince(now)
        if coolMore > 0 { try? await Task.sleep(nanoseconds: UInt64(coolMore * 1_000_000_000)) }
    }

    // MARK: - Standalone login (own account, self-refreshing)

    private var pendingLogin: (pkce: PKCE, state: String)?

    /// Create a PKCE pair + state and return the authorize URL to open in a
    /// browser. The callback page shows a code the user pastes back.
    func beginStandaloneLogin() -> URL {
        let pkce = PKCE.random()
        let state = OAuthFlow.randomState()
        pendingLogin = (pkce, state)
        return OAuthFlow.authorizeURL(pkce: pkce, state: state)
    }

    /// Exchange the pasted "code#state" for tokens, store them, and sync.
    func completeStandaloneLogin(pastedCode: String) async throws {
        guard let pending = pendingLogin else {
            throw ClaudeNetError.http(status: 0, body: "login not started")
        }
        let parsed = OAuthFlow.parsePastedCode(pastedCode)
        let tokens = try await ClaudeNet.exchange(
            code: parsed.code,
            verifier: pending.pkce.verifier,
            state: parsed.state ?? pending.state
        )
        try MacTokenStore.save(tokens)
        pendingLogin = nil
        consecutiveFailures = 0
        SyncLog.log("standalone login OK (expires \(Self.logFormatter.string(from: tokens.expiresAt)))")
        await sync()
    }

    /// Drop the standalone tokens; the app goes back to a signed-out state.
    func signOutStandalone() {
        MacTokenStore.clear()
        SyncLog.log("standalone signed out")
        connection = .notConnected
        Task { await sync() }
    }

    private func scheduleNextPoll() {
        timer?.invalidate()
        let interval = nextPollInterval()
        SyncLog.log("next poll in \(Int(interval))s (consecutiveFailures=\(consecutiveFailures))")
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            SyncLog.log("timer fired")
            Task { @MainActor in await self?.sync() }
        }
    }

    private func nextPollInterval() -> TimeInterval {
        guard consecutiveFailures > 0 else { return basePollInterval }
        // Doubles each consecutive failure, capped at maxPollInterval.
        let backoff = basePollInterval * pow(2.0, Double(min(consecutiveFailures, 10)))
        return min(backoff, maxPollInterval)
    }

    /// Whether the user has signed in with their own account.
    var isStandalone: Bool { MacTokenStore.load() != nil }

    /// A valid access token from the app's own login. When expired, refresh it
    /// (rotating our own refresh token) and persist the rotated pair — this is
    /// what keeps the app alive across long idle periods with no Claude Code
    /// running. Throws `NotSignedIn` when there's no token yet.
    private func currentToken() async throws -> String {
        guard let tokens = MacTokenStore.load() else { throw NotSignedIn() }
        guard tokens.isExpired() else { return tokens.accessToken }
        return try await refreshStandalone(tokens)
    }

    /// Exchange our refresh token for a fresh pair and persist it. Anthropic
    /// ROTATES the refresh token, so the returned one must be saved or the next
    /// refresh fails — `ClaudeNet.refresh` + `MacTokenStore.save` do exactly that.
    /// Each rotation also resets the ~29-day refresh window, so as long as the
    /// app refreshes within that window it stays signed in indefinitely. A dead
    /// refresh token surfaces as `StandaloneAuthExpired` → the UI asks for re-login.
    @discardableResult
    private func refreshStandalone(_ tokens: OAuthTokens) async throws -> String {
        SyncLog.log("standalone token expired — refreshing")
        do {
            let fresh = try await ClaudeNet.refresh(refreshToken: tokens.refreshToken)
            try MacTokenStore.save(fresh)
            SyncLog.log("standalone refresh OK (new expiry \(Self.logFormatter.string(from: fresh.expiresAt)))")
            return fresh.accessToken
        } catch {
            SyncLog.log("standalone refresh failed: \(error) — re-login needed")
            throw StandaloneAuthExpired()
        }
    }

    private static let logFormatter = ISO8601DateFormatter()

    #if DEBUG
    /// `TG_STANDALONE_TEST=deadrefresh` seeds a standalone token with an already-
    /// expired access token and a bogus refresh token, then removes it after the
    /// run. Proves the standalone branch is taken, self-refresh is attempted, a
    /// dead refresh token yields a clean re-login-needed state, and Claude Code's
    /// keychain is never touched. Does NOT use CC's refresh token (which would
    /// rotate and break the CLI).
    func seedFakeStandaloneTokenIfAsked() {
        guard ProcessInfo.processInfo.environment["TG_STANDALONE_TEST"] == "deadrefresh" else { return }
        let dead = OAuthTokens(
            accessToken: "sk-ant-oat01-fake-standalone-access",
            refreshToken: "sk-ant-ort01-fake-standalone-refresh",
            expiresAt: Date().addingTimeInterval(-60), // already expired → forces refresh
            scope: nil
        )
        try? MacTokenStore.save(dead)
        SyncLog.log("TEST: seeded a fake standalone token (dead refresh)")
    }
    #endif

    private func fetchUsageRefreshingTokenIfNeeded() async throws -> UsageResponse {
        do {
            return try await fetchUsage(token: try await currentToken(), attempts: 3)
        } catch let error as UsageClientError {
            guard case .http(let code, _) = error, code == 401 || code == 403 else { throw error }
            // Our access token was rejected (revoked, or a race where the account
            // refreshed elsewhere). Force a refresh with our own refresh token and
            // retry once; a dead refresh token surfaces as StandaloneAuthExpired.
            guard let tokens = MacTokenStore.load() else { throw error }
            let token = try await refreshStandalone(tokens)
            SyncLog.log("standalone refresh after \(code) — retrying")
            return try await fetchUsage(token: token, attempts: 2)
        }
    }

    private func applyUsage(_ usage: UsageResponse) {
        fiveHour = usage.fiveHour.utilization
        sevenDay = usage.sevenDay.utilization
        fiveHourResetsAt = usage.fiveHour.resetsAt
        sevenDayResetsAt = usage.sevenDay.resetsAt
        let before = accumulator.state.daily
        accumulator.apply(
            utilization: usage.sevenDay.utilization,
            resetAt: usage.sevenDay.resetsAt,
            now: Date(),
            fiveHour: usage.fiveHour.utilization
        )
        MacStateStore.save(accumulator.state)
        // Always refresh the in-memory grid — this is just a cheap local
        // recompute against the current Date(), and it's what makes today's
        // (empty) cell appear right after midnight even on a quiet night with
        // zero usage delta. Gating this behind "did the data change" (as we
        // used to) left the grid frozen on yesterday until usage resumed,
        // since a flat 0% delta never touched accumulator.state.daily.
        refreshGrid()
        // Push to iCloud on the first sync of a session (so new devices get the
        // current grass), then only when it actually changes — the KVS throttles
        // frequent writes, and 5-min polling is usually a no-op. Never push an
        // empty summary: on a fresh install (before iCloud has downloaded) that
        // would wipe the phone's grass.
        if !accumulator.state.daily.isEmpty, accumulator.state.daily != before || !hasPushedICloud {
            ICloudGrassStore.write(GrassPayload(daily: accumulator.state.daily, updatedAt: Date()))
            hasPushedICloud = true
        }
    }

    /// Fetch + parse with a short retry so transient blips (empty 200 from a
    /// dead connection after wake, a dropped request) self-heal within one sync.
    private func fetchUsage(token: String, attempts: Int) async throws -> UsageResponse {
        var lastError: Error = UsageClientError.badResponse
        for attempt in 0..<attempts {
            do {
                let data = try await UsageClient.fetchUsage(accessToken: token)
                return try UsageResponse.parse(data)
            } catch let error as UsageClientError {
                // Don't retry a real HTTP error (auth/quota) — only transient ones.
                if case .http = error { throw error }
                lastError = error
            } catch {
                lastError = error // decoding / URL errors: worth a retry
            }
            if attempt < attempts - 1 {
                try? await Task.sleep(nanoseconds: 2_000_000_000 * UInt64(attempt + 1))
            }
        }
        throw lastError
    }

    /// A dead token/refresh gets its own `.authExpired` state (fix: sign in
    /// again, not "wait and retry") — everything else is a generic `.error`.
    private static func connectionState(for error: Error) -> Connection {
        if error is StandaloneAuthExpired {
            return .authExpired("로그인이 만료됐어요. 설정에서 다시 로그인해 주세요.")
        }
        if let error = error as? UsageClientError, case .http(let code, _) = error, code == 401 || code == 403 {
            return .authExpired(friendlyMessage(for: error))
        }
        return .error(friendlyMessage(for: error))
    }

    private static func friendlyMessage(for error: Error) -> String {
        if let error = error as? UsageClientError {
            switch error {
            case .http(401, _), .http(403, _):
                return "로그인이 만료됐어요. 설정에서 다시 로그인해 주세요."
            case .http(429, _):
                return "요청이 많아 잠시 제한됐어요. 곧 자동으로 다시 시도합니다."
            case .http(let code, _):
                return "사용량 서버 오류 (HTTP \(code)). 곧 다시 시도합니다."
            case .empty, .badResponse:
                return "응답을 받지 못했어요. 네트워크 연결을 확인해 주세요. (자동 재시도 중)"
            }
        }
        if error is DecodingError {
            return "사용량 데이터를 읽지 못했어요. 잠시 후 자동으로 다시 시도합니다."
        }
        if (error as NSError).domain == NSURLErrorDomain {
            return "네트워크에 연결하지 못했어요. 연결을 확인해 주세요. (자동 재시도 중)"
        }
        return error.localizedDescription
    }

    private func refreshGrid() {
        grid = DateGrid.makeGrid(usage: accumulator.dailyCentipercent(), weeks: 26)
    }
}
