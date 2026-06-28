import SwiftUI

@main
struct TokenGrassMacApp: App {
    @StateObject private var service = UsageService()

    var body: some Scene {
        MenuBarExtra("TokenGrass", systemImage: "leaf.fill") {
            MenuContentView(service: service)
        }
        .menuBarExtraStyle(.window)
    }
}
