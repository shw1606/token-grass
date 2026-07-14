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
        XCTAssertEqual(utc.component(.hour, from: try XCTUnwrap(response.sevenDay.resetsAt)), 16)
        XCTAssertEqual(utc.component(.hour, from: try XCTUnwrap(response.fiveHour.resetsAt)), 22)
    }

    func testNullResetsAtIsOptionalNotFatal() throws {
        // Observed in the wild: the endpoint can return `resets_at: null` (seemingly
        // right around an actual window boundary). A single null field must not
        // take down the whole response — the utilization is still good data.
        let json = #"""
        {"five_hour":{"utilization":0.0,"resets_at":null},
         "seven_day":{"utilization":98.0,"resets_at":"2026-07-08T16:00:00.366178+00:00"}}
        """#.data(using: .utf8)!
        let response = try UsageResponse.parse(json)
        XCTAssertEqual(response.fiveHour.utilization, 0.0)
        XCTAssertNil(response.fiveHour.resetsAt)
        XCTAssertEqual(response.sevenDay.utilization, 98.0)
        XCTAssertNotNil(response.sevenDay.resetsAt)
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

    func testParsesScopedWeeklyFromLimits() throws {
        // Real shape: per-model weekly lives in `limits` as weekly_scoped, not a
        // `seven_day_<model>` field (those are null now).
        let json = """
        {"five_hour":{"utilization":2.0,"resets_at":"2026-07-14T07:59:59.543688+00:00"},
         "seven_day":{"utilization":48.0,"resets_at":"2026-07-15T15:59:59.543708+00:00"},
         "seven_day_sonnet":null,
         "limits":[
           {"kind":"session","group":"session","percent":2,"is_active":false,"resets_at":"2026-07-14T07:59:59.543688+00:00","scope":null},
           {"kind":"weekly_all","group":"weekly","percent":48,"is_active":false,"resets_at":"2026-07-15T15:59:59.543708+00:00","scope":null},
           {"kind":"weekly_scoped","group":"weekly","percent":57,"is_active":true,"resets_at":"2026-07-15T15:59:59.543963+00:00","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null}}
         ]}
        """.data(using: .utf8)!
        let r = try UsageResponse.parse(json)
        XCTAssertEqual(r.fiveHour.utilization, 2.0)
        XCTAssertEqual(r.sevenDay.utilization, 48.0)
        XCTAssertEqual(r.scopedWeekly?.modelName, "Fable")
        XCTAssertEqual(r.scopedWeekly?.utilization, 57)
        XCTAssertEqual(utc.component(.hour, from: try XCTUnwrap(r.scopedWeekly?.resetsAt)), 15)
    }

    func testNoLimitsMeansNoScopedWeekly() throws {
        let json = #"""
        {"five_hour":{"utilization":1,"resets_at":null},
         "seven_day":{"utilization":2,"resets_at":null}}
        """#.data(using: .utf8)!
        XCTAssertNil(try UsageResponse.parse(json).scopedWeekly)
    }

    func testPrefersActiveScopedWeekly() throws {
        let json = """
        {"five_hour":{"utilization":1,"resets_at":null},"seven_day":{"utilization":2,"resets_at":null},
         "limits":[
           {"kind":"weekly_scoped","percent":10,"is_active":false,"resets_at":null,"scope":{"model":{"display_name":"Opus"}}},
           {"kind":"weekly_scoped","percent":57,"is_active":true,"resets_at":null,"scope":{"model":{"display_name":"Fable"}}}
         ]}
        """.data(using: .utf8)!
        let sw = try UsageResponse.parse(json).scopedWeekly
        XCTAssertEqual(sw?.modelName, "Fable")
        XCTAssertEqual(sw?.utilization, 57)
    }

    func testFlexibleISO8601() {
        XCTAssertNotNil(ISO8601.flexible("2026-07-01T16:00:00.253187+00:00")) // microseconds
        XCTAssertNotNil(ISO8601.flexible("2026-07-01T16:00:00+00:00"))        // no fraction
        XCTAssertNotNil(ISO8601.flexible("2026-07-01T16:00:00.123+00:00"))    // milliseconds
        XCTAssertNil(ISO8601.flexible("not a date"))
    }
}
