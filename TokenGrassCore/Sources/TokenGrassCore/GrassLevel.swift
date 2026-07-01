import Foundation

/// GitHub-style 5-step intensity for a single cell.
public enum GrassLevel: Int, CaseIterable, Hashable, Sendable {
    case empty = 0
    case one
    case two
    case three
    case four
}

/// Percentile thresholds used to map a day's token count to a `GrassLevel`.
///
/// Normalization is percentile-based (not absolute) so the grass stays nicely
/// distributed even when daily usage varies a lot. Percentiles are computed over
/// the **non-zero** days in the window (zeros would drag p25 to 0).
///
/// Mapping (DESIGN §4.3):
///   level 0: tokens == 0
///   level 1: 0 < t <= p25
///   level 2: p25 < t <= p50
///   level 3: p50 < t <= p75
///   level 4: t > p75
public struct LevelThresholds: Equatable, Sendable {
    public let p25: Int
    public let p50: Int
    public let p75: Int

    public init(p25: Int, p50: Int, p75: Int) {
        self.p25 = p25
        self.p50 = p50
        self.p75 = p75
    }

    public static func compute(from tokens: [Int]) -> LevelThresholds {
        let nonZero = tokens.filter { $0 > 0 }
        let trimmed = removingHighOutliers(nonZero)
        return LevelThresholds(
            p25: percentile(trimmed, 25),
            p50: percentile(trimmed, 50),
            p75: percentile(trimmed, 75)
        )
    }

    /// Drop extreme high spikes (Tukey's upper fence, Q3 + 1.5·IQR) before
    /// quartiling, mirroring GitHub: a single record day shouldn't inflate the
    /// thresholds and wash the color out of every other day. The spike itself is
    /// still classified `.four` by `level(for:)` (it's above p75) — it just no
    /// longer drags the scale. Skipped when the sample is too small to judge
    /// outliers, and never trims the set to empty.
    static func removingHighOutliers(_ values: [Int]) -> [Int] {
        guard values.count >= 8 else { return values }
        let q1 = Double(percentile(values, 25))
        let q3 = Double(percentile(values, 75))
        let iqr = q3 - q1
        guard iqr > 0 else { return values }
        let fence = q3 + 1.5 * iqr
        let kept = values.filter { Double($0) <= fence }
        return kept.isEmpty ? values : kept
    }

    public func level(for tokens: Int) -> GrassLevel {
        if tokens <= 0 { return .empty }
        if tokens <= p25 { return .one }
        if tokens <= p50 { return .two }
        if tokens <= p75 { return .three }
        return .four
    }

    /// Linear-interpolation percentile (type-7), rounded to the nearest integer.
    public static func percentile(_ values: [Int], _ p: Double) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        if sorted.count == 1 { return sorted[0] }
        let rank = (p / 100.0) * Double(sorted.count - 1)
        let lo = Int(rank.rounded(.down))
        let hi = Int(rank.rounded(.up))
        let frac = rank - Double(lo)
        let value = Double(sorted[lo]) * (1 - frac) + Double(sorted[hi]) * frac
        return Int(value.rounded())
    }
}
