// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FlowClone",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "FlowClone", targets: ["FlowCloneApp"]),
        .library(name: "FlowCore", targets: ["FlowCore"]),
    ],
    targets: [
        // Pure logic core: state machine, session model, engine registry.
        // No AppKit — unit-testable via `swift test`.
        .target(
            name: "FlowCore"
        ),

        // The app itself: SwiftUI @main, MenuBarExtra, UI, dependency wiring.
        .executableTarget(
            name: "FlowCloneApp",
            dependencies: ["FlowCore"]
        ),

        .testTarget(
            name: "FlowCoreTests",
            dependencies: ["FlowCore"]
        ),
    ]
)
