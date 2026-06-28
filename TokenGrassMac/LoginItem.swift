import Foundation
import ServiceManagement

/// Launch-at-login via SMAppService (macOS 13+), so the menu-bar app is always
/// running and keeps accumulating daily usage even between manual launches.
@MainActor
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            // Best effort; ignore (e.g. unsigned dev builds may warn).
        }
    }
}
