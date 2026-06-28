import Foundation
import TokenGrassCore

/// Reads/writes the grass summary in iCloud key-value storage (shared between the
/// Mac companion and the iOS app via a common ubiquity-kvstore-identifier).
/// KVS has its own ~1MB allowance, separate from the user's iCloud Drive quota,
/// so a full iCloud doesn't break it. Without the entitlement it no-ops safely.
public enum ICloudGrassStore {
    public static let key = "grass.payload.v1"

    public static func write(_ payload: GrassPayload) {
        guard let data = payload.encoded() else { return }
        let store = NSUbiquitousKeyValueStore.default
        store.set(data, forKey: key)
        store.synchronize()
    }

    public static func read() -> GrassPayload? {
        guard let data = NSUbiquitousKeyValueStore.default.data(forKey: key) else { return nil }
        return GrassPayload.decode(data)
    }
}
