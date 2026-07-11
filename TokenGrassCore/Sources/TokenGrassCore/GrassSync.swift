import Foundation

/// Pure reconciliation rule for the iCloud-shared grass, kept out of the KVS
/// wrapper so it can be unit-tested. Both apps run this identically so a wipe on
/// one device propagates consistently to the others.
public enum GrassSync {
    public struct Resolution: Equatable {
        /// A newer reset the caller must honor: clear local history first.
        public let clearLocal: Bool
        /// Daily intensities to merge in (nil = nothing / stale-and-ignored).
        public let mergeDaily: [String: Double]?
        /// The reset the caller should persist as "last honored".
        public let honoredReset: Date?

        public init(clearLocal: Bool, mergeDaily: [String: Double]?, honoredReset: Date?) {
            self.clearLocal = clearLocal
            self.mergeDaily = mergeDaily
            self.honoredReset = honoredReset
        }
    }

    /// Decide what a device should do given the current iCloud state and the last
    /// reset it already honored.
    ///
    /// - A `reset` newer than `lastHonoredReset` means another device wiped:
    ///   clear local history and advance the honored marker.
    /// - A payload is merged only when it isn't stale relative to the reset — a
    ///   pre-reset re-push (`updatedAt <= reset`) is ignored so the wipe holds.
    public static func resolve(
        reset: Date?, payload: GrassPayload?, lastHonoredReset: Date?
    ) -> Resolution {
        var clearLocal = false
        var honored = lastHonoredReset
        if let reset, reset > (lastHonoredReset ?? .distantPast) {
            clearLocal = true
            honored = reset
        }

        var merge: [String: Double]?
        if let payload, !payload.daily.isEmpty, reset == nil || payload.updatedAt > reset! {
            merge = payload.daily
        }
        return Resolution(clearLocal: clearLocal, mergeDaily: merge, honoredReset: honored)
    }
}
