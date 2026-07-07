import Foundation
import SwiftUI
import AppKit
import TokenGrassCore

/// Reads the Claude Code keychain token, polls usage, accumulates daily
/// intensity, and publishes the grass + status to the UI.
@MainActor
final class UsageService: ObservableObject {
    enum Connection: Equatable {
        case unknown, notConnected, ok, error(String)
    }

    @Published private(set) var connection: Connection = .unknown
    @Published private(set) var fiveHour: Double = 0
    @Published private(set) var sevenDay: Double = 0
    @Published private(set) var fiveHourResetsAt: Date?
    @Published private(set) var sevenDayResetsAt: Date?
    @Published private(set) var lastSync: Date?
    @Published private(set) var grid: GrassGrid = DateGrid.makeGrid(usage: [:], weeks: 26)

    private var accumulator: UsageAccumulator
    private var timer: Timer?

    init() {
        accumulator = UsageAccumulator(state: MacStateStore.load(), calendar: .grass())
        // Restore from iCloud so a fresh install (or a brand-new Mac) picks up the
        // existing grass instead of starting blank. Merge keeps the larger value
        // per day, so a reinstall never loses what's already recorded.
        NSUbiquitousKeyValueStore.default.synchronize()
        if let cloud = ICloudGrassStore.read()?.daily { accumulator.mergeDaily(cloud) }
        refreshGrid()
        Task { await sync() }
        // Poll every 5 min while awake (the menu bar shows the % continuously)…
        timer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { await self?.sync() }
        }
        // …and catch up on wake from sleep (the timer doesn't fire while asleep).
        // Wait a few seconds first so networking is back up — a poll fired the
        // instant we wake often hits a dead connection and returns an empty 200.
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

    /// Cached so we don't hit the Keychain on every poll — reading Claude Code's
    /// item can pop a macOS permission prompt, and doing it every 5 minutes is
    /// what made the prompt recur. We read once, then only re-read when the token
    /// goes stale (a 401).
    private var cachedToken: String?
    /// Push to iCloud once per launch even if nothing changed, so a freshly
    /// installed iPhone/widget gets the current grass immediately.
    private var hasPushedICloud = false

    /// Guards against overlapping sync() calls — the 5-min timer, the wake
    /// handler, and a manual "다시 시도" tap can all land within moments of each
    /// other right after the Mac wakes from sleep, which otherwise fires several
    /// near-simultaneous requests and can trip a rate limit.
    private var isSyncing = false

    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let usage = try await fetchUsageRefreshingTokenIfNeeded()
            applyUsage(usage)
            lastSync = Date()
            connection = .ok
        } catch is KeychainError {
            connection = .notConnected
        } catch {
            connection = .error(Self.friendlyMessage(for: error))
        }
    }

    private func currentToken() async throws -> String {
        if let cachedToken { return cachedToken }
        let token = try await readTokenWithRetry()
        cachedToken = token
        return token
    }

    /// The macOS login Keychain can be briefly locked right after waking from
    /// sleep, before the user has unlocked their screen — a read attempted in
    /// that window fails even though Claude Code IS logged in. Retry a few times
    /// with a short delay before concluding it's genuinely not connected.
    private func readTokenWithRetry(attempts: Int = 4) async throws -> String {
        var lastError: Error = KeychainError.notFound
        for attempt in 0..<attempts {
            do {
                return try ClaudeKeychain.accessToken()
            } catch {
                lastError = error
                if attempt < attempts - 1 {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
        throw lastError
    }

    private func fetchUsageRefreshingTokenIfNeeded() async throws -> UsageResponse {
        do {
            return try await fetchUsage(token: try await currentToken(), attempts: 3)
        } catch let error as UsageClientError {
            // Token expired (Claude Code rotated it): drop the cache and re-read
            // once. Any other HTTP error propagates.
            if case .http(let code, _) = error, code == 401 || code == 403 {
                cachedToken = nil
                return try await fetchUsage(token: try await currentToken(), attempts: 2)
            }
            throw error
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
        // Push to iCloud on the first sync of a session (so new devices get the
        // current grass), then only when it actually changes — the KVS throttles
        // frequent writes, and 5-min polling is usually a no-op. Never push an
        // empty summary: on a fresh install (before iCloud has downloaded) that
        // would wipe the phone's grass.
        if !accumulator.state.daily.isEmpty, accumulator.state.daily != before || !hasPushedICloud {
            ICloudGrassStore.write(GrassPayload(daily: accumulator.state.daily, updatedAt: Date()))
            hasPushedICloud = true
            refreshGrid()
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

    private static func friendlyMessage(for error: Error) -> String {
        if let error = error as? UsageClientError {
            switch error {
            case .http(401, _), .http(403, _):
                return "인증이 만료된 것 같아요. 터미널에서 claude 를 한 번 실행해 로그인하세요."
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
