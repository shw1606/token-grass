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

    func testNilResetAtFallsBackToLastKnown() {
        // Observed in the wild: the endpoint can return resets_at: null. A poll
        // with no reset time must still accumulate (using the last known reset
        // time as a same-window reference) instead of the whole poll going to waste.
        var acc = UsageAccumulator(calendar: cal)
        acc.apply(utilization: 41, resetAt: weeklyReset, now: at(2026, 6, 27, 10))
        acc.apply(utilization: 43, resetAt: nil, now: at(2026, 6, 27, 14))
        XCTAssertEqual(acc.state.daily["2026-06-27"] ?? -1, 2.0, accuracy: 0.0001)
        // The last known reset time is preserved for the next poll's comparison.
        XCTAssertEqual(acc.state.lastResetAt, weeklyReset)
        // And a later poll with a real resets_at still detects the window correctly.
        acc.apply(utilization: 44, resetAt: weeklyReset, now: at(2026, 6, 27, 16))
        XCTAssertEqual(acc.state.daily["2026-06-27"] ?? -1, 3.0, accuracy: 0.0001)
    }

    func testNilResetAtOnFirstPollDoesNotCrash() {
        var acc = UsageAccumulator(calendar: cal)
        acc.apply(utilization: 41, resetAt: nil, now: at(2026, 6, 27, 10))
        XCTAssertTrue(acc.state.daily.isEmpty)
        XCTAssertNil(acc.state.lastResetAt)
        XCTAssertEqual(acc.state.lastValue, 41)
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

    func testMergeDailyRestoresAndKeepsLargerPerDay() {
        // Simulates a fresh install seeded from iCloud: empty local + cloud data.
        var fresh = UsageAccumulator(calendar: cal)
        XCTAssertTrue(fresh.mergeDaily(["2026-06-25": 5, "2026-06-26": 8]))
        XCTAssertEqual(fresh.state.daily, ["2026-06-25": 5, "2026-06-26": 8])

        // Merging keeps the larger value per day and never lowers an existing one.
        var acc = UsageAccumulator(state: AccumulatorState(daily: ["2026-06-25": 10, "2026-06-26": 3]), calendar: cal)
        let changed = acc.mergeDaily(["2026-06-25": 4, "2026-06-26": 9, "2026-06-27": 2])
        XCTAssertTrue(changed)
        XCTAssertEqual(acc.state.daily, ["2026-06-25": 10, "2026-06-26": 9, "2026-06-27": 2])
        // A merge with nothing larger reports no change.
        XCTAssertFalse(acc.mergeDaily(["2026-06-25": 1]))
    }

    func testFirstPollSeedsTodayFromFiveHour() {
        // A brand-new install: the first poll has no 7d delta, so today would be
        // empty — the 5-hour value seeds it so it isn't blank.
        var acc = UsageAccumulator(calendar: cal)
        acc.apply(utilization: 69, resetAt: weeklyReset, now: at(2026, 6, 27, 10), fiveHour: 30)
        XCTAssertEqual(acc.state.daily["2026-06-27"], 30)
        // Later polls add the real 7d delta on top of the seed.
        acc.apply(utilization: 74, resetAt: weeklyReset, now: at(2026, 6, 27, 14), fiveHour: 40)
        XCTAssertEqual(acc.state.daily["2026-06-27"], 35) // 30 + (74 - 69)
    }

    func testFiveHourSeedsOnlyOnFirstPoll() {
        var acc = UsageAccumulator(calendar: cal)
        acc.apply(utilization: 50, resetAt: weeklyReset, now: at(2026, 6, 27, 10), fiveHour: 20)
        acc.apply(utilization: 50, resetAt: weeklyReset, now: at(2026, 6, 27, 12), fiveHour: 80)
        XCTAssertEqual(acc.state.daily["2026-06-27"], 20) // no delta, no re-seed
    }
}
