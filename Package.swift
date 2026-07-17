// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Velo",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "Velo", targets: ["VeloApp"]),
        .library(name: "VeloCore", targets: ["VeloCore"]),
    ],
    dependencies: [
        // On-device Whisper (CoreML/ANE) for offline, private transcription.
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        // Pure logic core: state machine, session model, engine registry.
        // No AppKit — unit-testable via `swift test`.
        .target(
            name: "VeloCore"
        ),

        // Global hold-to-talk hotkey via CGEventTap.
        .target(
            name: "HotkeyService",
            dependencies: ["VeloCore"]
        ),

        // Objective-C shim: catch NSExceptions from Cocoa APIs (e.g. AVAudioEngine
        // installTap) and convert them to Swift errors so they can't abort() us.
        .target(
            name: "ObjCSupport"
        ),

        // Microphone capture via AVAudioEngine: audio level + (later) STT feed.
        .target(
            name: "AudioService",
            dependencies: ["ObjCSupport"]
        ),

        // The floating recording indicator (SwiftUI). A library so it can be
        // rendered headlessly in tests for visual verification.
        .target(
            name: "IndicatorUI"
        ),

        // Speech-to-text engines: Apple SpeechAnalyzer, Groq Whisper (cloud),
        // WhisperKit (on-device).
        .target(
            name: "TranscriptionKit",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
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

        // v2 Command Mode: read selection, speak an edit, replace it.
        .target(
            name: "CommandModeKit",
            dependencies: ["CleanupKit", "InjectionKit"]
        ),

        // Local persistence: Keychain (secrets) + SwiftData models/stores.
        .target(
            name: "PersistenceKit"
        ),

        // Data-driven settings views (dictionary, app profiles, history). A
        // library so they render headlessly in tests.
        .target(
            name: "SettingsUI",
            dependencies: ["PersistenceKit", "LearningKit"]
        ),

        // First-run onboarding walkthrough (presentational; snapshot-testable).
        .target(
            name: "OnboardingUI"
        ),

        // The app itself: SwiftUI @main, MenuBarExtra, UI, dependency wiring.
        .executableTarget(
            name: "VeloApp",
            dependencies: [
                "VeloCore", "HotkeyService", "AudioService", "IndicatorUI",
                "TranscriptionKit", "InjectionKit", "CleanupKit", "PersistenceKit",
                "SettingsUI", "LearningKit", "OnboardingUI", "CommandModeKit",
            ]
        ),

        .testTarget(
            name: "VeloCoreTests",
            dependencies: ["VeloCore"]
        ),
        .testTarget(
            name: "HotkeyServiceTests",
            dependencies: ["HotkeyService"]
        ),
        .testTarget(
            name: "AudioServiceTests",
            dependencies: ["AudioService", "ObjCSupport"]
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
        .testTarget(
            name: "OnboardingUITests",
            dependencies: ["OnboardingUI"]
        ),
        .testTarget(
            name: "CommandModeKitTests",
            dependencies: ["CommandModeKit"]
        ),
    ]
)
