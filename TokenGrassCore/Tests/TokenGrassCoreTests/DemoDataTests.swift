import XCTest
@testable import TokenGrassCore

final class DemoDataTests: XCTestCase {
    private let calendar = Calendar.grass(timeZone: TimeZone(identifier: "UTC")!, firstWeekday: 1)

    private func fixedToday() -> Date {
        var components = DateComponents()
        components.year = 2026; components.month = 6; components.day = 26
        return calendar.date(from: components)!
    }

    func testDeterministicForSameSeed() {
        let a = DemoData.usage(today: fixedToday(), weeks: 8, calendar: calendar, seed: 42)
        let b = DemoData.usage(today: fixedToday(), weeks: 8, calendar: calendar, seed: 42)
        XCTAssertEqual(a, b)
        XCTAssertFalse(a.isEmpty)
    }

    func testValuesAreSaneAndCoverTheWindow() {
        let weeks = 8
        let usage = DemoData.usage(today: fixedToday(), weeks: weeks, calendar: calendar, seed: 7)
        let keys = DateGrid.realDateKeys(today: fixedToday(), weeks: weeks, calendar: calendar)

        // Demo fills exactly the rendered window.
        XCTAssertEqual(Set(usage.keys), Set(keys))

        XCTAssertTrue(usage.values.allSatisfy { $0 >= 0 })
        XCTAssertTrue(usage.values.allSatisfy { $0 <= 200_000 })
        XCTAssertTrue(usage.values.contains { $0 > 0 }, "Demo should produce some green")
    }
}
