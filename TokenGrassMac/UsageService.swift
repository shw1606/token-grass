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
        // …and catch up immediately on wake from sleep (the timer doesn't fire while asleep).
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.sync() }
        }
    }

    var hasData: Bool { !accumulator.state.daily.isEmpty }

    func sync() async {
        let token: String
        do {
            token = try ClaudeKeychain.accessToken()
        } catch {
            connection = .notConnected
            return
        }

        do {
            let data = try await UsageClient.fetchUsage(accessToken: token)
            let usage = try UsageResponse.parse(data)
            fiveHour = usage.fiveHour.utilization
            sevenDay = usage.sevenDay.utilization
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
            lastSync = Date()
            connection = .ok
        } catch {
            connection = .error(error.localizedDescription)
        }
    }

    private func refreshGrid() {
        grid = DateGrid.makeGrid(usage: accumulator.dailyCentipercent(), weeks: 26)
    }
}
