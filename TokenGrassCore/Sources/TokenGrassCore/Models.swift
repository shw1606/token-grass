import Foundation

/// One day's token usage. `date` is a local-midnight-boundary day key, "yyyy-MM-dd".
public struct DailyUsage: Codable, Hashable, Sendable {
    public let date: String
    public let totalTokens: Int

    public init(date: String, totalTokens: Int) {
        self.date = date
        self.totalTokens = totalTokens
    }
}

/// The aggregated window the widget renders. Persisted to the App Group by the app.
public struct UsageSnapshot: Codable, Sendable {
    public let days: [DailyUsage]
    public let lastUpdated: Date
    /// Largest single-day token count in the window (kept for display / future scaling).
    public let maxTokensInWindow: Int

    public init(days: [DailyUsage], lastUpdated: Date, maxTokensInWindow: Int) {
        self.days = days
        self.lastUpdated = lastUpdated
        self.maxTokensInWindow = maxTokensInWindow
    }
}

public extension UsageSnapshot {
    /// Build a snapshot from a `[dayKey: tokens]` map, sorting days ascending.
    static func make(from usage: [String: Int], lastUpdated: Date) -> UsageSnapshot {
        let days = usage.keys.sorted().map { DailyUsage(date: $0, totalTokens: usage[$0] ?? 0) }
        let maxTokens = days.map(\.totalTokens).max() ?? 0
        return UsageSnapshot(days: days, lastUpdated: lastUpdated, maxTokensInWindow: maxTokens)
    }

    /// Convenience `[dayKey: tokens]` view for fast lookups while rendering.
    var usageByDay: [String: Int] {
        Dictionary(days.map { ($0.date, $0.totalTokens) }, uniquingKeysWith: { _, new in new })
    }
}
