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

        // Global hold-to-talk hotkey via CGEventTap.
        .target(
            name: "HotkeyService",
            dependencies: ["FlowCore"]
        ),

        // Microphone capture via AVAudioEngine: audio level + (later) STT feed.
        .target(
            name: "AudioService"
        ),

        // The floating recording indicator (SwiftUI). A library so it can be
        // rendered headlessly in tests for visual verification.
        .target(
            name: "IndicatorUI"
        ),

        // The app itself: SwiftUI @main, MenuBarExtra, UI, dependency wiring.
        .executableTarget(
            name: "FlowCloneApp",
            dependencies: ["FlowCore", "HotkeyService", "AudioService", "IndicatorUI"]
        ),

        .testTarget(
            name: "FlowCoreTests",
            dependencies: ["FlowCore"]
        ),
        .testTarget(
            name: "HotkeyServiceTests",
            dependencies: ["HotkeyService"]
        ),
        .testTarget(
            name: "IndicatorUITests",
            dependencies: ["IndicatorUI"]
        ),
    ]
)
