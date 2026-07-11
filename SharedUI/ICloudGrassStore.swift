import Foundation
import TokenGrassCore

/// Reads/writes the grass summary in iCloud key-value storage (shared between the
/// Mac companion and the iOS app via a common ubiquity-kvstore-identifier).
/// KVS has its own ~1MB allowance, separate from the user's iCloud Drive quota,
/// so a full iCloud doesn't break it. Without the entitlement it no-ops safely.
public enum ICloudGrassStore {
    public static let key = "grass.payload.v1"
    /// A "wipe happened at this time" tombstone, kept in a SEPARATE key so it
    /// survives a data push overwriting the payload. Devices honor a reset newer
    /// than the last one they've seen by clearing their own local history and
    /// ignoring any payload that predates it — this is what makes Danger Zone's
    /// "delete everywhere" actually stick instead of being resurrected by another
    /// device's max-merge re-push.
    public static let resetKey = "grass.resetAt.v1"

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

    public static func readReset() -> Date? {
        let t = NSUbiquitousKeyValueStore.default.double(forKey: resetKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    /// Record a wipe and drop the current payload. Other devices honor this on
    /// their next read (see `resolve`).
    public static func clear(resetAt: Date) {
        let store = NSUbiquitousKeyValueStore.default
        store.removeObject(forKey: key)
        store.set(resetAt.timeIntervalSince1970, forKey: resetKey)
        store.synchronize()
    }

    /// Read the current iCloud state and apply the shared tombstone rule
    /// (`GrassSync.resolve`), so both apps reconcile identically.
    public static func resolve(lastHonoredReset: Date?) -> GrassSync.Resolution {
        GrassSync.resolve(reset: readReset(), payload: read(), lastHonoredReset: lastHonoredReset)
    }
}
