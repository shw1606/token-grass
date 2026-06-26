import XCTest
@testable import TokenGrassCore

final class AppGroupStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: AppGroupStore!

    override func setUp() {
        super.setUp()
        suiteName = "TokenGrassCoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = AppGroupStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testRoundTrip() throws {
        let snapshot = UsageSnapshot.make(
            from: ["2026-06-25": 1000, "2026-06-26": 2000],
            lastUpdated: Date(timeIntervalSince1970: 1_750_000_000)
        )
        try store.save(snapshot)

        let loaded = store.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.days, snapshot.days)
        XCTAssertEqual(loaded?.maxTokensInWindow, 2000)
    }

    func testLoadEmptyReturnsNil() {
        XCTAssertNil(store.load())
    }

    func testClearRemovesSnapshot() throws {
        try store.save(DemoData.snapshot(weeks: 4))
        XCTAssertNotNil(store.load())
        store.clear()
        XCTAssertNil(store.load())
    }
}
