import Foundation

/// Persisted accumulator state (this is what syncs to iCloud, ~KB).
/// `daily` maps day → usage intensity (% of the weekly limit attributed to that
/// day). `last*` is the previous poll snapshot used for diffing.
public struct AccumulatorState: Codable, Equatable, Sendable {
    public var daily: [String: Double]
    public var lastValue: Double?
    public var lastAt: Date?
    public var lastResetAt: Date?

    public init(
        daily: [String: Double] = [:],
        lastValue: Double? = nil,
        lastAt: Date? = nil,
        lastResetAt: Date? = nil
    ) {
        self.daily = daily
        self.lastValue = lastValue
        self.lastAt = lastAt
        self.lastResetAt = lastResetAt
    }
}

/// Turns a stream of `seven_day.utilization` readings into per-day intensities.
///
/// `seven_day` is a cumulative counter that climbs until its weekly `resets_at`
/// (confirmed: 41% → 43% across polls with the same reset). So each day's usage
/// is the *rise* in utilization since the last poll, distributed evenly across
/// any calendar days the gap spans (Mac may be off for a while). No backfill:
/// the very first poll only establishes a baseline.
public struct UsageAccumulator {
    public private(set) var state: AccumulatorState
    private let calendar: Calendar
    private let windowTolerance: TimeInterval
    private let retentionDays: Int

    public init(
        state: AccumulatorState = .init(),
        calendar: Calendar = .grass(),
        windowTolerance: TimeInterval = 120,
        retentionDays: Int = 731
    ) {
        self.state = state
        self.calendar = calendar
        self.windowTolerance = windowTolerance
        self.retentionDays = retentionDays
    }

    /// Apply one poll. `utilization` = `seven_day.utilization`, `resetAt` = its `resets_at`.
    public mutating func apply(utilization: Double, resetAt: Date, now: Date) {
        defer { prune(now: now) }

        guard
            let lastValue = state.lastValue,
            let lastAt = state.lastAt,
            let lastResetAt = state.lastResetAt
        else {
            snapshot(utilization, now, resetAt) // first poll = baseline only
            return
        }

        // resets_at carries per-poll microsecond jitter, so compare with tolerance.
        let sameWindow = abs(resetAt.timeIntervalSince(lastResetAt)) < windowTolerance
        let delta = sameWindow ? max(0, utilization - lastValue) : max(0, utilization)

        let days = dayKeys(from: lastAt, to: now)
        if delta > 0, !days.isEmpty {
            let share = delta / Double(days.count)
            for key in days { state.daily[key, default: 0] += share }
        }
        snapshot(utilization, now, resetAt)
    }

    /// Day → integer "centi-percent" (×100) so the existing Int-based grid/level
    /// pipeline renders it unchanged. 2.5% → 250.
    public func dailyCentipercent() -> [String: Int] {
        state.daily.mapValues { Int(($0 * 100).rounded()) }
    }

    /// Merge in daily intensities restored from elsewhere (e.g. iCloud on a fresh
    /// install), keeping the larger value per day so nothing already recorded is lost.
    /// Returns true if anything changed.
    @discardableResult
    public mutating func mergeDaily(_ daily: [String: Double]) -> Bool {
        var changed = false
        for (day, value) in daily where value > (state.daily[day] ?? 0) {
            state.daily[day] = value
            changed = true
        }
        return changed
    }

    // MARK: - Internals

    private mutating func snapshot(_ value: Double, _ at: Date, _ resetAt: Date) {
        state.lastValue = value
        state.lastAt = at
        state.lastResetAt = resetAt
    }

    private func dayKeys(from start: Date, to end: Date) -> [String] {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        guard endDay >= startDay else { return [] }

        let formatter = DateGrid.dayKeyFormatter(calendar: calendar)
        var keys: [String] = []
        var day = startDay
        while day <= endDay {
            keys.append(formatter.string(from: day))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return keys
    }

    private mutating func prune(now: Date) {
        guard let cutoff = calendar.date(
            byAdding: .day, value: -retentionDays, to: calendar.startOfDay(for: now)
        ) else { return }
        let cutoffKey = DateGrid.dayKeyFormatter(calendar: calendar).string(from: cutoff)
        state.daily = state.daily.filter { $0.key >= cutoffKey }
    }
}
