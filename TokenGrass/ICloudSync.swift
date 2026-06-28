import Foundation
import WidgetKit
import TokenGrassCore

/// Pulls the grass summary from iCloud (written by the Mac companion), mirrors it
/// into the App Group for the widget, and reloads the widget. Refreshes on launch
/// and whenever iCloud reports an external change.
@MainActor
final class ICloudSync: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?

    init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(externalChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default
        )
        NSUbiquitousKeyValueStore.default.synchronize()
        pull()
    }

    func pull() {
        guard let payload = ICloudGrassStore.read() else { return }
        let snap = payload.snapshot()
        snapshot = snap
        if let store = AppGroupStore() { try? store.save(snap) }
        WidgetCenter.shared.reloadAllTimelines()
    }

    @objc private func externalChange() {
        Task { @MainActor in self.pull() }
    }
}
