import Foundation
import BackgroundTasks

/// Opportunistic background polling so the widget stays reasonably fresh even
/// when the app isn't opened. iOS decides the actual cadence; we ask for ~4h.
/// Registration must happen before the app finishes launching (App.init).
enum BackgroundRefresh {
    static let taskID = "dev.yulebuilds.tokengrass.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refresh)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        // Duplicate submissions just replace the pending request; errors here
        // (e.g. Background App Refresh disabled) are non-fatal by design.
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule() // keep the chain alive
        let work = Task { @MainActor in
            await PhoneUsageService.shared.sync()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}
