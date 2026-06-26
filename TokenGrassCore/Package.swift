// swift-tools-version: 5.9
import PackageDescription

// TokenGrassCore — pure, Foundation-only logic shared by the app and the widget.
// No SwiftUI / WidgetKit here on purpose: this module compiles & unit-tests on a
// plain macOS toolchain (no Xcode required), which is how the grass math is verified.
let package = Package(
    name: "TokenGrassCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v12), // for headless `swift test`
    ],
    products: [
        .library(name: "TokenGrassCore", targets: ["TokenGrassCore"]),
    ],
    targets: [
        .target(name: "TokenGrassCore"),
        .testTarget(name: "TokenGrassCoreTests", dependencies: ["TokenGrassCore"]),
    ]
)
