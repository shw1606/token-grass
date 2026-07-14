import Foundation

/// One rate-limit window from `/api/oauth/usage`. `utilization` is a percentage
/// (0–100) of an opaque limit; the endpoint exposes **no token counts**.
public struct UsageWindow: Equatable, Sendable {
    public let utilization: Double
    /// Observed in the wild: the endpoint can return `resets_at: null` (seemingly
    /// right around an actual window boundary). Optional so that doesn't take
    /// down the whole response — a missing reset time just means we can't show
    /// a countdown/clock for this window this poll.
    public let resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
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
        if let raw = try container.decodeIfPresent(String.self, forKey: .resetsAt) {
            // A present-but-unparseable string is still a real problem — fail loud.
            guard let date = ISO8601.flexible(raw) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .resetsAt, in: container,
                    debugDescription: "Unparseable resets_at: \(raw)"
                )
            }
            self.resetsAt = date
        } else {
            self.resetsAt = nil
        }
    }
}

/// A per-model weekly limit (e.g. Fable's own weekly tally), reported in the
/// endpoint's `limits` array as a `weekly_scoped` entry. `modelName` is the
/// human label ("Fable", "Opus", …); parsing it generically means the tile
/// tracks whichever model the plan scopes, not a hard-coded one.
public struct ScopedWeekly: Equatable, Sendable {
    public let modelName: String
    public let utilization: Double
    public let resetsAt: Date?

    public init(modelName: String, utilization: Double, resetsAt: Date?) {
        self.modelName = modelName
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

/// The subset of `/api/oauth/usage` we use. Extra keys (spend, extra_usage, …)
/// are ignored — loose parsing so schema drift degrades gracefully.
public struct UsageResponse: Sendable {
    public let fiveHour: UsageWindow
    public let sevenDay: UsageWindow
    public let sevenDaySonnet: UsageWindow?
    /// Per-model weekly (from `limits[].weekly_scoped`), e.g. Fable.
    public let scopedWeekly: ScopedWeekly?

    public init(
        fiveHour: UsageWindow, sevenDay: UsageWindow,
        sevenDaySonnet: UsageWindow? = nil, scopedWeekly: ScopedWeekly? = nil
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDaySonnet = sevenDaySonnet
        self.scopedWeekly = scopedWeekly
    }

    public static func parse(_ data: Data) throws -> UsageResponse {
        try JSONDecoder().decode(UsageResponse.self, from: data)
    }
}

extension UsageResponse: Decodable {
    private enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case limits
    }

    /// One entry of the endpoint's `limits` array.
    private struct Limit: Decodable {
        let kind: String?
        let percent: Double?
        let resetsAt: String?
        let isActive: Bool?
        let scope: Scope?

        struct Scope: Decodable {
            let model: Model?
            struct Model: Decodable {
                let displayName: String?
                enum CodingKeys: String, CodingKey { case displayName = "display_name" }
            }
        }
        enum CodingKeys: String, CodingKey {
            case kind, percent, isActive = "is_active", scope
            case resetsAt = "resets_at"
        }
        var modelName: String? { scope?.model?.displayName }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = try c.decode(UsageWindow.self, forKey: .fiveHour)
        sevenDay = try c.decode(UsageWindow.self, forKey: .sevenDay)
        sevenDaySonnet = try c.decodeIfPresent(UsageWindow.self, forKey: .sevenDaySonnet)
        let limits = (try? c.decodeIfPresent([Limit].self, forKey: .limits)) ?? nil
        scopedWeekly = Self.scopedWeekly(from: limits)
    }

    private static func scopedWeekly(from limits: [Limit]?) -> ScopedWeekly? {
        guard let limits else { return nil }
        let scoped = limits.filter { $0.kind == "weekly_scoped" && $0.modelName != nil }
        // Prefer the active scoped limit; fall back to the first with a model.
        guard let l = scoped.first(where: { $0.isActive == true }) ?? scoped.first,
              let name = l.modelName, let percent = l.percent else { return nil }
        return ScopedWeekly(modelName: name, utilization: percent, resetsAt: l.resetsAt.flatMap(ISO8601.flexible))
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
