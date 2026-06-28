import XCTest
@testable import TokenGrassCore

final class UsageResponseTests: XCTestCase {
    private let utc = Calendar.grass(timeZone: TimeZone(identifier: "UTC")!)

    func testParsesRealResponse() throws {
        // Trimmed copy of the actual /api/oauth/usage body (microsecond fractions, null dollars, extra keys).
        let json = """
        {"five_hour":{"utilization":0.0,"resets_at":"2026-06-27T22:00:00.315020+00:00","limit_dollars":null},
         "seven_day":{"utilization":41.0,"resets_at":"2026-07-01T16:00:00.315048+00:00","limit_dollars":null},
         "seven_day_sonnet":{"utilization":4.0,"resets_at":"2026-07-01T16:00:00.315057+00:00"},
         "extra_usage":{"used_credits":2661.0,"monthly_limit":2300},
         "spend":{"percent":100}}
        """.data(using: .utf8)!

        let response = try UsageResponse.parse(json)
        XCTAssertEqual(response.fiveHour.utilization, 0.0)
        XCTAssertEqual(response.sevenDay.utilization, 41.0)
        XCTAssertEqual(response.sevenDaySonnet?.utilization, 4.0)
        // Microsecond fraction parsed down to the right instant.
        XCTAssertEqual(utc.component(.hour, from: response.sevenDay.resetsAt), 16)
        XCTAssertEqual(utc.component(.hour, from: response.fiveHour.resetsAt), 22)
    }

    func testNullSonnetIsOptional() throws {
        let json = #"""
        {"five_hour":{"utilization":1,"resets_at":"2026-06-27T22:00:00+00:00"},
         "seven_day":{"utilization":2,"resets_at":"2026-07-01T16:00:00+00:00"},
         "seven_day_sonnet":null}
        """#.data(using: .utf8)!
        let response = try UsageResponse.parse(json)
        XCTAssertNil(response.sevenDaySonnet)
        XCTAssertEqual(response.fiveHour.utilization, 1)
    }

    func testFlexibleISO8601() {
        XCTAssertNotNil(ISO8601.flexible("2026-07-01T16:00:00.253187+00:00")) // microseconds
        XCTAssertNotNil(ISO8601.flexible("2026-07-01T16:00:00+00:00"))        // no fraction
        XCTAssertNotNil(ISO8601.flexible("2026-07-01T16:00:00.123+00:00"))    // milliseconds
        XCTAssertNil(ISO8601.flexible("not a date"))
    }
}
