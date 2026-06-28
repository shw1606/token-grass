import Foundation

/// One rate-limit window from `/api/oauth/usage`. `utilization` is a percentage
/// (0–100) of an opaque limit; the endpoint exposes **no token counts**.
public struct UsageWindow: Equatable, Sendable {
    public let utilization: Double
    public let resetsAt: Date

    public init(utilization: Double, resetsAt: Date) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

extension UsageWindow: Decodable {
    private enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.utilization = try container.decode(Double.self, forKey: .utilization)
        let raw = try container.decode(String.self, forKey: .resetsAt)
        guard let date = ISO8601.flexible(raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .resetsAt, in: container,
                debugDescription: "Unparseable resets_at: \(raw)"
            )
        }
        self.resetsAt = date
    }
}

/// The subset of `/api/oauth/usage` we use. Extra keys (limits, spend,
/// extra_usage, …) are ignored — loose parsing so schema drift degrades gracefully.
public struct UsageResponse: Decodable, Sendable {
    public let fiveHour: UsageWindow
    public let sevenDay: UsageWindow
    public let sevenDaySonnet: UsageWindow?

    private enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
    }

    public init(fiveHour: UsageWindow, sevenDay: UsageWindow, sevenDaySonnet: UsageWindow? = nil) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDaySonnet = sevenDaySonnet
    }

    public static func parse(_ data: Data) throws -> UsageResponse {
        try JSONDecoder().decode(UsageResponse.self, from: data)
    }
}

public enum ISO8601 {
    /// Parses ISO-8601 with or without fractional seconds. The endpoint sends
    /// microseconds ("2026-07-01T16:00:00.253187+00:00") which the system
    /// formatter (millisecond precision) can reject — so we strip the fraction
    /// and retry. Second-level precision is all we need (windows compared ±120s).
    public static func flexible(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }

        let stripped = string.replacingOccurrences(
            of: #"\.\d+"#, with: "", options: .regularExpression
        )
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: stripped)
    }
}
