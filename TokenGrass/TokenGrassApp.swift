import SwiftUI

@main
struct TokenGrassApp: App {
    @StateObject private var service: PhoneUsageService
    @Environment(\.scenePhase) private var scenePhase

    init() {
        _service = StateObject(wrappedValue: PhoneUsageService.shared)
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView(service: service)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await PhoneUsageService.shared.syncIfStale() }
            case .background:
                BackgroundRefresh.schedule()
            default:
                break
            }
        }
    }
}
