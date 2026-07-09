import Foundation

/// Reads/writes the usage snapshot in the shared App Group container.
/// The app writes; the widget reads. No tokens here — those live in the Keychain.
public struct AppGroupStore {
    public static let suiteName = "group.dev.yulebuilds.tokengrass"
    public static let snapshotKey = "usage.snapshot.v1"

    private let defaults: UserDefaults

    /// Real App Group store. Returns `nil` if the suite isn't available
    /// (e.g. the entitlement is missing).
    public init?(suiteName: String = AppGroupStore.suiteName) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        self.defaults = defaults
    }

    /// Injectable initializer for tests.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func save(_ snapshot: UsageSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        defaults.set(data, forKey: Self.snapshotKey)
    }

    public func load() -> UsageSnapshot? {
        guard let data = defaults.data(forKey: Self.snapshotKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    public func clear() {
        defaults.removeObject(forKey: Self.snapshotKey)
    }

    // MARK: - Accumulator state (standalone iPhone mode)

    /// The phone's own `AccumulatorState` lives here too: the app polls, the
    /// widget only reads the derived snapshot above.
    public static let accumulatorKey = "accumulator.state.v1"

    public func saveAccumulator(_ state: AccumulatorState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        defaults.set(try encoder.encode(state), forKey: Self.accumulatorKey)
    }

    public func loadAccumulator() -> AccumulatorState? {
        guard let data = defaults.data(forKey: Self.accumulatorKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AccumulatorState.self, from: data)
    }
}
