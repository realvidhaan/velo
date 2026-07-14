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

        // Speech-to-text engines (Apple SpeechAnalyzer; Groq Whisper later).
        .target(
            name: "TranscriptionKit"
        ),

        // Text injection into the focused app (paste primary, keystroke fallback).
        .target(
            name: "InjectionKit"
        ),

        // LLM cleanup engines + app-aware formatting.
        .target(
            name: "CleanupKit"
        ),

        // Deterministic "learning": diff user corrections into dictionary rules.
        .target(
            name: "LearningKit"
        ),

        // Local persistence: Keychain (secrets) + SwiftData models/stores.
        .target(
            name: "PersistenceKit"
        ),

        // Data-driven settings views (dictionary, app profiles, history). A
        // library so they render headlessly in tests.
        .target(
            name: "SettingsUI",
            dependencies: ["PersistenceKit"]
        ),

        // The app itself: SwiftUI @main, MenuBarExtra, UI, dependency wiring.
        .executableTarget(
            name: "FlowCloneApp",
            dependencies: [
                "FlowCore", "HotkeyService", "AudioService", "IndicatorUI",
                "TranscriptionKit", "InjectionKit", "CleanupKit", "PersistenceKit",
                "SettingsUI", "LearningKit",
            ]
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
        .testTarget(
            name: "TranscriptionKitTests",
            dependencies: ["TranscriptionKit"]
        ),
        .testTarget(
            name: "InjectionKitTests",
            dependencies: ["InjectionKit"]
        ),
        .testTarget(
            name: "CleanupKitTests",
            dependencies: ["CleanupKit"]
        ),
        .testTarget(
            name: "PersistenceKitTests",
            dependencies: ["PersistenceKit"]
        ),
        .testTarget(
            name: "SettingsUITests",
            dependencies: ["SettingsUI"]
        ),
        .testTarget(
            name: "LearningKitTests",
            dependencies: ["LearningKit"]
        ),
    ]
)
