import XCTest
@testable import TokenGrassCore

final class DateGridTests: XCTestCase {
    // Pinned, deterministic calendar/date for structural assertions.
    private let calendar = Calendar.grass(timeZone: TimeZone(identifier: "UTC")!, firstWeekday: 1)

    private func fixedToday() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 26
        components.hour = 15 // mid-day; startOfDay should normalize this away
        return calendar.date(from: components)!
    }

    func testGridShape() {
        let grid = DateGrid.makeGrid(usage: [:], today: fixedToday(), weeks: 4, calendar: calendar)
        XCTAssertEqual(grid.columns.count, 4)
        XCTAssertTrue(grid.columns.allSatisfy { $0.count == 7 })
        XCTAssertEqual(grid.allCells.count, 28)
    }

    func testTodayIsTheMostRecentRealCell() {
        let grid = DateGrid.makeGrid(usage: ["2026-06-26": 1234], today: fixedToday(), weeks: 4, calendar: calendar)
        let realKeys = grid.allCells.compactMap { $0.dateKey }
        XCTAssertEqual(realKeys.max(), "2026-06-26")

        let todayCell = grid.allCells.first { $0.dateKey == "2026-06-26" }
        XCTAssertNotNil(todayCell)
        XCTAssertEqual(todayCell?.tokens, 1234)
        XCTAssertEqual(todayCell?.isFuture, false)
    }

    func testFutureCellsAreEmptyAndTrailing() {
        let grid = DateGrid.makeGrid(usage: [:], today: fixedToday(), weeks: 4, calendar: calendar)
        // Future padding only ever appears at the very end (last column).
        let cells = grid.allCells
        let firstFuture = cells.firstIndex { $0.isFuture }
        if let firstFuture {
            XCTAssertTrue(cells[firstFuture...].allSatisfy { $0.isFuture })
        }
        for cell in cells {
            if cell.isFuture {
                XCTAssertNil(cell.dateKey)
                XCTAssertEqual(cell.tokens, 0)
            } else {
                XCTAssertNotNil(cell.dateKey)
            }
        }
    }

    func testRealDaysAreContiguousAndUnique() {
        let grid = DateGrid.makeGrid(usage: [:], today: fixedToday(), weeks: 6, calendar: calendar)
        let keys = grid.allCells.compactMap { $0.dateKey }

        // Unique
        XCTAssertEqual(Set(keys).count, keys.count)

        // Strictly increasing by exactly one day
        let formatter = DateGrid.dayKeyFormatter(calendar: calendar)
        let dates = keys.map { formatter.date(from: $0)! }
        for i in 1..<dates.count {
            let delta = calendar.dateComponents([.day], from: dates[i - 1], to: dates[i]).day
            XCTAssertEqual(delta, 1, "Gap between \(keys[i - 1]) and \(keys[i])")
        }
    }

    func testRealDateKeysMatchesGrid() {
        let keys = DateGrid.realDateKeys(today: fixedToday(), weeks: 5, calendar: calendar)
        let gridKeys = DateGrid.makeGrid(usage: [:], today: fixedToday(), weeks: 5, calendar: calendar)
            .allCells.compactMap { $0.dateKey }
        XCTAssertEqual(keys, gridKeys)
        XCTAssertEqual(keys.last, "2026-06-26")
    }
}
