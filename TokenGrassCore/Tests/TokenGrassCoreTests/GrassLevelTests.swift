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

    func testSmallSamplesAreNotTrimmed() {
        // Below the 8-day sample floor, outlier removal is skipped entirely.
        let values = [1, 1, 1, 2, 2, 3, 500]
        XCTAssertEqual(LevelThresholds.removingHighOutliers(values), values)
    }

    func testHighOutlierIsDroppedFromThresholds() {
        // Nine steady days plus one record spike. The spike (Q3 + 1.5·IQR fence)
        // must be excluded so it doesn't inflate p75.
        let steady = [10, 12, 11, 13, 10, 12, 11, 13, 12]
        let withSpike = steady + [10_000]

        let trimmed = LevelThresholds.removingHighOutliers(withSpike)
        XCTAssertFalse(trimmed.contains(10_000))
        XCTAssertEqual(trimmed.sorted(), steady.sorted())

        // Thresholds match the steady-only set — the spike doesn't move the scale…
        XCTAssertEqual(LevelThresholds.compute(from: withSpike),
                       LevelThresholds.compute(from: steady))
        // …yet the spike day is still the darkest level.
        XCTAssertEqual(LevelThresholds.compute(from: withSpike).level(for: 10_000), .four)
    }

    func testNoOutlierLeavesDataIntact() {
        // A tight spread has no Tukey outliers, so nothing is dropped.
        let values = [10, 12, 11, 13, 10, 12, 11, 13, 12, 14]
        XCTAssertEqual(LevelThresholds.removingHighOutliers(values).sorted(), values.sorted())
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
