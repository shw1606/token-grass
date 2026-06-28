import SwiftUI

@main
struct TokenGrassApp: App {
    @StateObject private var sync = ICloudSync()

    var body: some Scene {
        WindowGroup {
            RootView(sync: sync)
        }
    }
}
