import Foundation

/// The small summary the Mac companion syncs to iPhone via iCloud (a few KB).
/// `daily` maps "yyyy-MM-dd" → usage intensity (% of the weekly limit).
public struct GrassPayload: Codable, Sendable, Equatable {
    public let daily: [String: Double]
    public let updatedAt: Date

    public init(daily: [String: Double], updatedAt: Date) {
        self.daily = daily
        self.updatedAt = updatedAt
    }

    public func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(self)
    }

    public static func decode(_ data: Data) -> GrassPayload? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GrassPayload.self, from: data)
    }

    /// Convert to the widget's `UsageSnapshot` (intensity % → centi-percent Int).
    public func snapshot() -> UsageSnapshot {
        let usage = daily.mapValues { Int(($0 * 100).rounded()) }
        return UsageSnapshot.make(from: usage, lastUpdated: updatedAt)
    }
}
