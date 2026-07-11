import XCTest
@testable import TokenGrassCore

final class GrassSyncTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func payload(_ daily: [String: Double], at: Date) -> GrassPayload {
        GrassPayload(daily: daily, updatedAt: at)
    }

    func testNoReset_mergesPayload() {
        let r = GrassSync.resolve(
            reset: nil, payload: payload(["d": 3], at: t0), lastHonoredReset: nil)
        XCTAssertFalse(r.clearLocal)
        XCTAssertEqual(r.mergeDaily, ["d": 3])
    }

    func testNewReset_clearsLocalAndHonors() {
        let reset = t0.addingTimeInterval(100)
        let r = GrassSync.resolve(
            reset: reset, payload: nil, lastHonoredReset: nil)
        XCTAssertTrue(r.clearLocal)
        XCTAssertEqual(r.honoredReset, reset)
        XCTAssertNil(r.mergeDaily)
    }

    func testAlreadyHonoredReset_doesNotClearAgain() {
        let reset = t0.addingTimeInterval(100)
        let r = GrassSync.resolve(
            reset: reset, payload: nil, lastHonoredReset: reset)
        XCTAssertFalse(r.clearLocal)
    }

    func testStalePayloadAfterReset_isIgnored() {
        // A pre-reset re-push (updatedAt <= reset) must not resurrect the grass.
        let reset = t0.addingTimeInterval(100)
        let r = GrassSync.resolve(
            reset: reset,
            payload: payload(["old": 9], at: t0), // updatedAt before reset
            lastHonoredReset: nil)
        XCTAssertTrue(r.clearLocal)
        XCTAssertNil(r.mergeDaily) // stale → ignored
    }

    func testFreshPayloadAfterReset_isMerged() {
        // Post-reset data (updatedAt > reset) is legitimate and must merge.
        let reset = t0.addingTimeInterval(100)
        let r = GrassSync.resolve(
            reset: reset,
            payload: payload(["new": 4], at: t0.addingTimeInterval(200)),
            lastHonoredReset: nil)
        XCTAssertTrue(r.clearLocal)
        XCTAssertEqual(r.mergeDaily, ["new": 4])
    }

    func testEmptyPayload_mergesNothing() {
        let r = GrassSync.resolve(reset: nil, payload: payload([:], at: t0), lastHonoredReset: nil)
        XCTAssertNil(r.mergeDaily)
    }
}
