import Foundation
import Combine
import WidgetKit
import TokenGrassCore

/// Standalone engine for the iPhone: signs in with the user's own Claude
/// account (OAuth, tokens in the iOS Keychain), polls `/api/oauth/usage`
/// directly from the phone, accumulates per-day intensities, and feeds the
/// widget. iCloud data pushed by the Mac companion is max-merged in, so both
/// sources coexist without double counting — per-day values converge to the
/// larger of the two observations.
@MainActor
final class PhoneUsageService: ObservableObject {
    static let shared = PhoneUsageService()

    @Published private(set) var isLoggedIn = false
    /// True when polling hit a definitive 401/403 and a re-login is the fix.
    @Published private(set) var needsRelogin = false
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var fiveHour: Double = 0
    @Published private(set) var sevenDay: Double = 0
    @Published private(set) var fiveHourResetsAt: Date?
    @Published private(set) var sevenDayResetsAt: Date?
    @Published private(set) var lastSync: Date?
    @Published private(set) var isBusy = false
    @Published private(set) var lastError: String?

    private var accumulator: UsageAccumulator
    private var pendingLogin: (pkce: PKCE, state: String)?
    private var lastAttemptAt: Date?
    private var lastPushedDaily: [String: Double]?
    /// Guards against burst re-syncs (rapid foregrounding, pull-to-refresh spam).
    private let minSyncInterval: TimeInterval = 10

    private init() {
        let store = AppGroupStore()
        accumulator = UsageAccumulator(state: store?.loadAccumulator() ?? AccumulatorState())

        #if DEBUG
        injectTokensFromEnvironmentIfAsked()
        #endif
        isLoggedIn = ClaudeTokenStore.load() != nil

        NotificationCenter.default.addObserver(
            self, selector: #selector(iCloudChanged),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default
        )
        NSUbiquitousKeyValueStore.default.synchronize()
        mergeICloud()
        publishSnapshot()

        if isLoggedIn { Task { await sync() } }
    }

    // MARK: - Login

    /// Create the PKCE pair + state and hand back the URL to open in Safari.
    func beginLogin() -> URL {
        let pkce = PKCE.random()
        let state = OAuthFlow.randomState()
        pendingLogin = (pkce, state)
        return OAuthFlow.authorizeURL(pkce: pkce, state: state)
    }

    /// Exchange the code the user copied off the callback page ("code#state").
    func completeLogin(pastedCode: String) async throws {
        guard let pending = pendingLogin else {
            throw ClaudeNetError.http(status: 0, body: "login not started")
        }
        let parsed = OAuthFlow.parsePastedCode(pastedCode)
        let tokens = try await ClaudeNet.exchange(
            code: parsed.code,
            verifier: pending.pkce.verifier,
            state: parsed.state ?? pending.state
        )
        try ClaudeTokenStore.save(tokens)
        pendingLogin = nil
        isLoggedIn = true
        needsRelogin = false
        lastError = nil
        await sync(force: true)
    }

    /// Drop the tokens; keep the grass — it's the user's history.
    func signOut() {
        ClaudeTokenStore.clear()
        isLoggedIn = false
        needsRelogin = false
        fiveHour = 0
        sevenDay = 0
        fiveHourResetsAt = nil
        sevenDayResetsAt = nil
        lastSync = nil
        lastError = nil
    }

    // MARK: - Sync

    /// Poll once. When logged out this still folds in whatever the Mac pushed
    /// to iCloud, so the screen stays fresh either way.
    func sync(force: Bool = false) async {
        mergeICloud()
        guard isLoggedIn else { publishSnapshot(); return }
        guard !isBusy else { return }
        if !force, let last = lastAttemptAt, Date().timeIntervalSince(last) < minSyncInterval {
            return
        }
        lastAttemptAt = Date()
        isBusy = true
        defer { isBusy = false }

        do {
            let token = try await freshAccessToken()
            var usage: UsageResponse
            do {
                usage = try await ClaudeNet.fetchUsage(accessToken: token)
            } catch let error as ClaudeNetError where error.status == 401 || error.status == 403 {
                // Expired mid-flight? One forced refresh, one retry.
                let refreshed = try await forceRefresh()
                usage = try await ClaudeNet.fetchUsage(accessToken: refreshed)
            }
            apply(usage)
            lastError = nil
            needsRelogin = false
        } catch let error as ClaudeNetError where error.status == 401 || error.status == 403 {
            needsRelogin = true
            lastError = "Your Claude session has expired. Sign in again to keep syncing."
        } catch let error as ClaudeNetError where error.status == 429 {
            lastError = "Rate limited by Anthropic — will retry later."
        } catch {
            lastError = "Couldn't reach Anthropic. Check your connection and try again."
        }
    }

    /// Foreground-activation hook: skip if we synced moments ago.
    func syncIfStale(maxAge: TimeInterval = 120) async {
        if let last = lastSync, Date().timeIntervalSince(last) < maxAge {
            mergeICloud()
            publishSnapshot()
            return
        }
        await sync()
    }

    // MARK: - Tokens

    private func freshAccessToken() async throws -> String {
        guard let tokens = ClaudeTokenStore.load() else {
            throw ClaudeNetError.http(status: 401, body: "not logged in")
        }
        if tokens.isExpired(), !tokens.refreshToken.isEmpty {
            return try await forceRefresh()
        }
        return tokens.accessToken
    }

    /// Refresh grant. Anthropic rotates refresh tokens, so always persist the
    /// pair that comes back — the old refresh token is dead after this.
    private func forceRefresh() async throws -> String {
        guard let tokens = ClaudeTokenStore.load(), !tokens.refreshToken.isEmpty else {
            throw ClaudeNetError.http(status: 401, body: "no refresh token")
        }
        let fresh = try await ClaudeNet.refresh(refreshToken: tokens.refreshToken)
        try ClaudeTokenStore.save(fresh)
        return fresh.accessToken
    }

    // MARK: - Data plumbing

    private func apply(_ usage: UsageResponse) {
        let now = Date()
        fiveHour = usage.fiveHour.utilization
        sevenDay = usage.sevenDay.utilization
        fiveHourResetsAt = usage.fiveHour.resetsAt
        sevenDayResetsAt = usage.sevenDay.resetsAt
        lastSync = now

        accumulator.apply(
            utilization: usage.sevenDay.utilization,
            resetAt: usage.sevenDay.resetsAt,
            now: now,
            fiveHour: usage.fiveHour.utilization
        )
        mergeICloud()
        publishSnapshot()
        pushToICloud()
    }

    private var lastHonoredReset: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: "tokengrass.lastHonoredResetAt")
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set { UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "tokengrass.lastHonoredResetAt") }
    }

    /// Reconcile with iCloud: honor a wipe done on another device (clear local
    /// first), then fold in any non-stale grass (max per day — see
    /// `UsageAccumulator.mergeDaily` and `ICloudGrassStore.resolve`).
    private func mergeICloud() {
        let r = ICloudGrassStore.resolve(lastHonoredReset: lastHonoredReset)
        if r.clearLocal {
            accumulator = UsageAccumulator(state: AccumulatorState())
            lastHonoredReset = r.honoredReset
        }
        if let daily = r.mergeDaily { accumulator.mergeDaily(daily) }
    }

    /// Persist + hand the derived snapshot to the UI and the widget.
    private func publishSnapshot() {
        let store = AppGroupStore()
        try? store?.saveAccumulator(accumulator.state)

        guard !accumulator.state.daily.isEmpty else {
            snapshot = nil
            return
        }
        let snap = UsageSnapshot.make(from: accumulator.dailyCentipercent(), lastUpdated: Date())
        snapshot = snap
        try? store?.save(snap)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Share what the phone learned back over iCloud (so a fresh Mac install —
    /// or another device — can restore it). Skipped when nothing changed.
    private func pushToICloud() {
        let daily = accumulator.state.daily
        guard !daily.isEmpty, daily != lastPushedDaily else { return }
        ICloudGrassStore.write(GrassPayload(daily: daily, updatedAt: Date()))
        lastPushedDaily = daily
    }

    @objc private func iCloudChanged() {
        Task { @MainActor in
            self.mergeICloud()
            self.publishSnapshot()
        }
    }

    // MARK: - Debug

    #if DEBUG
    /// E2E-test hook: `TG_INJECT_TOKEN_FILE=<path to OAuthTokens JSON>` seeds
    /// the Keychain so a simulator run can exercise the logged-in path without
    /// a browser. Debug builds only; the file itself never leaves the machine.
    private func injectTokensFromEnvironmentIfAsked() {
        guard let path = ProcessInfo.processInfo.environment["TG_INJECT_TOKEN_FILE"],
              let data = FileManager.default.contents(atPath: path) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let tokens = try? decoder.decode(OAuthTokens.self, from: data) {
            try? ClaudeTokenStore.save(tokens)
        }
    }
    #endif
}
