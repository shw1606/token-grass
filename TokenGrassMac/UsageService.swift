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
    }

    var hasData: Bool { !accumulator.state.daily.isEmpty }

    /// Cached so we don't hit the Keychain on every poll — reading Claude Code's
    /// item can pop a macOS permission prompt, and doing it every 5 minutes is
    /// what made the prompt recur. We read once, then only re-read when the token
    /// goes stale (a 401).
    private var cachedToken: String?

    func sync() async {
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

    private func currentToken() throws -> String {
        if let cachedToken { return cachedToken }
        let token = try ClaudeKeychain.accessToken()
        cachedToken = token
        return token
    }

    private func fetchUsageRefreshingTokenIfNeeded() async throws -> UsageResponse {
        do {
            return try await fetchUsage(token: try currentToken(), attempts: 3)
        } catch let error as UsageClientError {
            // Token expired (Claude Code rotated it): drop the cache and re-read
            // once. Any other HTTP error propagates.
            if case .http(let code, _) = error, code == 401 || code == 403 {
                cachedToken = nil
                return try await fetchUsage(token: try currentToken(), attempts: 2)
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
            now: Date()
        )
        MacStateStore.save(accumulator.state)
        // Only push to iCloud when the grass actually changed — the KVS
        // throttles frequent writes, and 5-min polling usually is a no-op.
        if accumulator.state.daily != before {
            ICloudGrassStore.write(GrassPayload(daily: accumulator.state.daily, updatedAt: Date()))
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
