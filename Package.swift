// swift-tools-version: 5.9
import PackageDescription

// The `Locked` app target uses SwiftUI/AppKit and only builds on macOS.
// Everything else (LockedShared, LockedBridge, LockedWatchdog and the tests) is
// Foundation-only and also builds on Linux, so CI/dev boxes without a Mac can run
// `swift build` and `swift test`. On non-Apple hosts we simply leave the app target
// out of the package graph; `swift test` would otherwise try to compile it.
#if os(macOS)
let includeApp = true
#else
let includeApp = false
#endif

var products: [Product] = [
    .library(name: "LockedShared", targets: ["LockedShared"]),
    .executable(name: "LockedBridge", targets: ["LockedBridge"]),
    .executable(name: "LockedWatchdog", targets: ["LockedWatchdog"]),
]

var targets: [Target] = [
    .target(
        name: "LockedShared",
        path: "Sources/LockedShared"
    ),
    // Testable logic for the native messaging host (framing, state messages, controller).
    .target(
        name: "LockedBridgeCore",
        dependencies: ["LockedShared"],
        path: "Sources/LockedBridgeCore"
    ),
    .executableTarget(
        name: "LockedBridge",
        dependencies: ["LockedShared", "LockedBridgeCore"],
        path: "Sources/LockedBridge"
    ),
    .executableTarget(
        name: "LockedWatchdog",
        dependencies: ["LockedShared"],
        path: "Sources/LockedWatchdog"
    ),
    .testTarget(
        name: "LockedSharedTests",
        dependencies: ["LockedShared"],
        path: "Tests/LockedSharedTests"
    ),
    .testTarget(
        name: "LockedBridgeTests",
        dependencies: ["LockedBridgeCore", "LockedShared"],
        path: "Tests/LockedBridgeTests"
    ),
]

if includeApp {
    products.insert(.executable(name: "Locked", targets: ["Locked"]), at: 0)
    targets.append(
        .executableTarget(
            name: "Locked",
            dependencies: ["LockedShared"],
            path: "Sources/Locked"
        )
    )
}

let package = Package(
    name: "Locked",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets,
    swiftLanguageVersions: [.v5]
)
