import Foundation

/// Tiny deterministic PRNG (LCG) so demo grass is stable and unit-testable.
/// `Date.now`/`Math.random` are intentionally avoided — same seed ⇒ same grass.
struct LCG {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }

    /// Uniform double in [0, 1).
    mutating func nextDouble() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0) // 2^53
    }
}

/// Plausible-looking fake usage for: demo mode, widget placeholder, and the
/// "fake data but it's on my home screen 🌱" launch screenshot.
public enum DemoData {
    public static func usage(
        today: Date = Date(),
        weeks: Int = 53,
        calendar: Calendar = .grass(),
        seed: UInt64 = 42
    ) -> [String: Int] {
        let calendar = calendar
        let todayStart = calendar.startOfDay(for: today)
        let weekday = calendar.component(.weekday, from: todayStart)
        let offsetFromWeekStart = (weekday - calendar.firstWeekday + 7) % 7

        guard
            let currentWeekStart = calendar.date(byAdding: .day, value: -offsetFromWeekStart, to: todayStart),
            let gridStart = calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: currentWeekStart)
        else { return [:] }

        let formatter = DateGrid.dayKeyFormatter(calendar: calendar)
        var rng = LCG(seed: seed)
        var result: [String: Int] = [:]

        var day = gridStart
        while day <= todayStart {
            let wd = calendar.component(.weekday, from: day)
            let isWeekend = (wd == 1 || wd == 7)
            let roll = rng.nextDouble()

            let tokens: Int
            if roll < 0.15 {
                tokens = 0 // a chunk of empty days keeps the grass realistic
            } else {
                let base = isWeekend ? 8_000.0 : 35_000.0
                let spread = isWeekend ? 12_000.0 : 40_000.0
                let spike = rng.nextDouble() < 0.07 ? 2.2 : 1.0
                tokens = Int((base + rng.nextDouble() * spread) * spike)
            }
            result[formatter.string(from: day)] = tokens
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }
        return result
    }

    public static func snapshot(
        today: Date = Date(),
        weeks: Int = 53,
        calendar: Calendar = .grass(),
        seed: UInt64 = 42
    ) -> UsageSnapshot {
        UsageSnapshot.make(from: usage(today: today, weeks: weeks, calendar: calendar, seed: seed), lastUpdated: today)
    }
}
