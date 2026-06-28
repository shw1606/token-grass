import XCTest
@testable import TokenGrassCore

final class UsageAccumulatorTests: XCTestCase {
    private let cal = Calendar.grass(timeZone: TimeZone(identifier: "UTC")!, firstWeekday: 1)
    private let weeklyReset = makeDate(2026, 7, 1, 16)

    private static func makeDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12) -> Date {
        Calendar.grass(timeZone: TimeZone(identifier: "UTC")!)
            .date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
    }
    private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
    }

    func testFirstPollIsBaselineOnly() {
        var acc = UsageAccumulator(calendar: cal)
        acc.apply(utilization: 41, resetAt: weeklyReset, now: at(2026, 6, 27))
        XCTAssertTrue(acc.state.daily.isEmpty) // pre-existing usage not attributable
        XCTAssertEqual(acc.state.lastValue, 41)
    }

    func testSameDayIncrement() {
        var acc = UsageAccumulator(calendar: cal)
        acc.apply(utilization: 41, resetAt: weeklyReset, now: at(2026, 6, 27, 10))
        acc.apply(utilization: 43, resetAt: weeklyReset, now: at(2026, 6, 27, 14))
        XCTAssertEqual(acc.state.daily["2026-06-27"] ?? -1, 2.0, accuracy: 0.0001)
    }

    func testMicrosecondJitterStillSameWindow() {
        var acc = UsageAccumulator(calendar: cal)
        acc.apply(utilization: 41, resetAt: weeklyReset, now: at(2026, 6, 27, 10))
        // resets_at jitters by ~1s between polls; must NOT be treated as a new window.
        acc.apply(utilization: 43, resetAt: weeklyReset.addingTimeInterval(1.2), now: at(2026, 6, 27, 14))
        XCTAssertEqual(acc.state.daily["2026-06-27"] ?? -1, 2.0, accuracy: 0.0001)
    }

    func testGapDistributesEvenlyAcrossSpannedDays() {
        var acc = UsageAccumulator(calendar: cal)
        acc.apply(utilization: 40, resetAt: weeklyReset, now: at(2026, 6, 24, 12))
        acc.apply(utilization: 49, resetAt: weeklyReset, now: at(2026, 6, 27, 12)) // +9 over a 3-day gap
        // Spans 6/24..6/27 inclusive = 4 day buckets → 9/4 = 2.25 each.
        for day in ["2026-06-24", "2026-06-25", "2026-06-26", "2026-06-27"] {
            XCTAssertEqual(acc.state.daily[day] ?? -1, 2.25, accuracy: 0.0001, day)
        }
    }

    func testWeeklyResetCrossingCountsNewWindow() {
        var acc = UsageAccumulator(calendar: cal)
        acc.apply(utilization: 90, resetAt: weeklyReset, now: at(2026, 6, 30, 12))
        let nextWeek = at(2026, 7, 8, 16)
        // Reset happened between polls → delta = new window value (5), not 5-90.
        acc.apply(utilization: 5, resetAt: nextWeek, now: at(2026, 7, 2, 12))
        let spanned = ["2026-06-30", "2026-07-01", "2026-07-02"] // 3 days
        for day in spanned {
            XCTAssertEqual(acc.state.daily[day] ?? -1, 5.0 / 3.0, accuracy: 0.0001, day)
        }
    }

    func testNegativeDeltaClampedToZero() {
        var acc = UsageAccumulator(calendar: cal)
        acc.apply(utilization: 50, resetAt: weeklyReset, now: at(2026, 6, 27, 10))
        acc.apply(utilization: 48, resetAt: weeklyReset, now: at(2026, 6, 27, 14)) // dip
        XCTAssertEqual(acc.state.daily["2026-06-27"] ?? 0, 0, accuracy: 0.0001)
    }

    func testCentipercentBridge() {
        var acc = UsageAccumulator(calendar: cal)
        acc.apply(utilization: 40, resetAt: weeklyReset, now: at(2026, 6, 27, 10))
        acc.apply(utilization: 42.5, resetAt: weeklyReset, now: at(2026, 6, 27, 14))
        XCTAssertEqual(acc.dailyCentipercent()["2026-06-27"], 250)
    }

    func testRetentionPrunesOldDays() {
        var acc = UsageAccumulator(calendar: cal, retentionDays: 30)
        acc.apply(utilization: 10, resetAt: weeklyReset, now: at(2026, 1, 1, 10))
        acc.apply(utilization: 20, resetAt: weeklyReset, now: at(2026, 1, 1, 14)) // writes 2026-01-01
        XCTAssertNotNil(acc.state.daily["2026-01-01"])
        // A poll far in the future prunes the old day.
        acc.apply(utilization: 21, resetAt: weeklyReset, now: at(2026, 6, 27, 12))
        XCTAssertNil(acc.state.daily["2026-01-01"])
    }
}
