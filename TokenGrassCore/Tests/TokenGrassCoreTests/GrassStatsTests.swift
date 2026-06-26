import XCTest
@testable import TokenGrassCore

final class GrassStatsTests: XCTestCase {
    private let calendar = Calendar.grass(timeZone: TimeZone(identifier: "UTC")!, firstWeekday: 1)

    private func fixedToday() -> Date {
        var components = DateComponents()
        components.year = 2026; components.month = 6; components.day = 26
        return calendar.date(from: components)!
    }

    func testStats() {
        let usage = ["2026-06-26": 100, "2026-06-25": 200] // today + yesterday
        let grid = DateGrid.makeGrid(usage: usage, today: fixedToday(), weeks: 2, calendar: calendar)
        XCTAssertEqual(grid.todayTokens, 100)
        XCTAssertEqual(grid.lastWeekTokens, 300)  // last 7 days: 100 + 200 + zeros
        XCTAssertEqual(grid.totalTokens, 300)
        XCTAssertEqual(grid.activeDayCount, 2)
    }

    func testMonthLabels() {
        let grid = DateGrid.makeGrid(usage: [:], today: fixedToday(), weeks: 53, calendar: calendar)
        let labels = DateGrid.monthLabels(for: grid, calendar: calendar)

        XCTAssertFalse(labels.isEmpty)
        // Strictly increasing column positions.
        for i in 1..<labels.count {
            XCTAssertLessThan(labels[i - 1].columnIndex, labels[i].columnIndex)
        }
        // Three-letter English month abbreviations.
        XCTAssertTrue(labels.allSatisfy { $0.title.count == 3 })
        // A year window should surface ~12-13 month ticks.
        XCTAssertGreaterThanOrEqual(labels.count, 12)
    }

    func testTokenFormat() {
        XCTAssertEqual(TokenFormat.compact(0), "0")
        XCTAssertEqual(TokenFormat.compact(999), "999")
        XCTAssertEqual(TokenFormat.compact(1_000), "1k")
        XCTAssertEqual(TokenFormat.compact(12_345), "12.3k")
        XCTAssertEqual(TokenFormat.compact(1_200_000), "1.2M")
        XCTAssertEqual(TokenFormat.compact(-1_500), "-1.5k")
    }
}
