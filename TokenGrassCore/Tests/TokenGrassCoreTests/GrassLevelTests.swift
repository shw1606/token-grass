import XCTest
@testable import TokenGrassCore

final class GrassLevelTests: XCTestCase {
    func testPercentileType7Interpolation() {
        let values = [10, 20, 30, 40]
        XCTAssertEqual(LevelThresholds.percentile(values, 25), 18) // 17.5 -> 18
        XCTAssertEqual(LevelThresholds.percentile(values, 50), 25) // exactly 25
        XCTAssertEqual(LevelThresholds.percentile(values, 75), 33) // 32.5 -> 33
    }

    func testPercentileEdgeCases() {
        XCTAssertEqual(LevelThresholds.percentile([], 50), 0)
        XCTAssertEqual(LevelThresholds.percentile([99], 50), 99)
    }

    func testThresholdsIgnoreZeroDays() {
        // Zeros must not drag the percentiles down.
        let withZeros = LevelThresholds.compute(from: [0, 0, 10, 20, 30, 40])
        let withoutZeros = LevelThresholds.compute(from: [10, 20, 30, 40])
        XCTAssertEqual(withZeros, withoutZeros)
    }

    func testLevelBoundaries() {
        // nonZero = [10,20,30,40] -> p25=18, p50=25, p75=33
        let t = LevelThresholds.compute(from: [10, 20, 30, 40])
        XCTAssertEqual(t, LevelThresholds(p25: 18, p50: 25, p75: 33))

        XCTAssertEqual(t.level(for: 0), .empty)
        XCTAssertEqual(t.level(for: -5), .empty)
        XCTAssertEqual(t.level(for: 1), .one)
        XCTAssertEqual(t.level(for: 18), .one)   // == p25 -> level 1
        XCTAssertEqual(t.level(for: 19), .two)
        XCTAssertEqual(t.level(for: 25), .two)   // == p50 -> level 2
        XCTAssertEqual(t.level(for: 26), .three)
        XCTAssertEqual(t.level(for: 33), .three) // == p75 -> level 3
        XCTAssertEqual(t.level(for: 34), .four)
        XCTAssertEqual(t.level(for: 999_999), .four)
    }
}
