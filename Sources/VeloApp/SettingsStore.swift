import Foundation
import SwiftUI
import ServiceManagement
import HotkeyService
import PersistenceKit

/// User-facing preferences, backed by `UserDefaults` (and Keychain for the API
/// key). Observable so the Settings UI and controller stay in sync.
@MainActor
final class SettingsStore: ObservableObject {
    private let defaults = UserDefaults.standard

    enum Keys {
        static let hotkeyModifier = "hotkey.modifier"
        static let cleanupEngine = "cleanup.engine"
        static let ollamaModel = "cleanup.ollamaModel"
        static let groqModel = "cleanup.groqModel"
        static let groqSmartModel = "cleanup.groqSmartModel"
        static let sttEngine = "stt.engine"
        static let trimSilence = "stt.trimSilence"
        static let voiceProcessing = "stt.voiceProcessing"
        static let learnFromCorrections = "learning.enabled"
        static let hasCompletedOnboarding = "onboarding.completed"
        static let commandModifier = "command.modifier"
        static let commandModeEnabled = "command.enabled"
        static let launchAtLoginDefaulted = "launchAtLogin.defaulted"
        static let voiceProcessingReset = "stt.voiceProcessing.reset"
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }

    enum CleanupChoice: String, CaseIterable, Identifiable {
        case auto          // Groq if key present, else local polish
        case groq
        case appleFoundation
        case ollama
        case localOnly
        var id: String { rawValue }
        var label: String {
            switch self {
            case .auto: return "Automatic (Groq if key set, else local)"
            case .groq: return "Groq (cloud)"
            case .appleFoundation: return "Apple Foundation Models (local)"
            case .ollama: return "Ollama (local)"
            case .localOnly: return "Local polish only (no LLM)"
            }
        }
    }

    enum STTChoice: String, CaseIterable, Identifiable {
        case auto          // Groq if key set → WhisperKit if installed → Apple
        case groqWhisper
        case whisperKit
        case appleSpeech
        var id: String { rawValue }
        var label: String {
            switch self {
            case .auto: return "Automatic (Groq → on-device Whisper → Apple)"
            case .groqWhisper: return "Groq Whisper (cloud)"
            case .whisperKit: return "WhisperKit (on-device, ~600 MB)"
            case .appleSpeech: return "Apple Speech (on-device, built-in)"
            }
        }
    }

    @Published var hotkeyModifier: Hotkey.Modifier {
        didSet { defaults.set(hotkeyModifier.rawValue, forKey: Keys.hotkeyModifier) }
    }
    @Published var cleanupChoice: CleanupChoice {
        didSet { defaults.set(cleanupChoice.rawValue, forKey: Keys.cleanupEngine) }
    }
    @Published var sttChoice: STTChoice {
        didSet { defaults.set(sttChoice.rawValue, forKey: Keys.sttEngine) }
    }
    @Published var trimSilence: Bool {
        didSet { defaults.set(trimSilence, forKey: Keys.trimSilence) }
    }
    /// Apple voice processing (AGC + noise suppression + echo cancel) on the mic.
    /// The user-facing "Whisper & noise reduction" switch.
    @Published var voiceProcessing: Bool {
        didSet { defaults.set(voiceProcessing, forKey: Keys.voiceProcessing) }
    }
    @Published var ollamaModel: String {
        didSet { defaults.set(ollamaModel, forKey: Keys.ollamaModel) }
    }
    /// Fast model — the always-on cleanup pass on every dictation.
    @Published var groqModel: String {
        didSet { defaults.set(groqModel, forKey: Keys.groqModel) }
    }
    /// Stronger model — used for harder passes (reformatting, long transcripts,
    /// dictionary-term corrections, Command Mode) where the fast model slips.
    @Published var groqSmartModel: String {
        didSet { defaults.set(groqSmartModel, forKey: Keys.groqSmartModel) }
    }
    /// Not persisted directly here — read/written through the Keychain.
    @Published var groqAPIKey: String {
        didSet { KeychainStore.set(groqAPIKey, for: .groqAPIKey) }
    }
    @Published var launchAtLogin: Bool {
        didSet { updateLaunchAtLogin(launchAtLogin) }
    }
    @Published var learnFromCorrections: Bool {
        didSet { defaults.set(learnFromCorrections, forKey: Keys.learnFromCorrections) }
    }
    @Published var commandModifier: Hotkey.Modifier {
        didSet { defaults.set(commandModifier.rawValue, forKey: Keys.commandModifier) }
    }
    @Published var commandModeEnabled: Bool {
        didSet { defaults.set(commandModeEnabled, forKey: Keys.commandModeEnabled) }
    }

    init() {
        let modRaw = defaults.string(forKey: Keys.hotkeyModifier) ?? Hotkey.Modifier.fn.rawValue
        hotkeyModifier = Hotkey.Modifier(rawValue: modRaw) ?? .fn
        let choiceRaw = defaults.string(forKey: Keys.cleanupEngine) ?? CleanupChoice.auto.rawValue
        cleanupChoice = CleanupChoice(rawValue: choiceRaw) ?? .auto
        let sttRaw = defaults.string(forKey: Keys.sttEngine) ?? STTChoice.auto.rawValue
        sttChoice = STTChoice(rawValue: sttRaw) ?? .auto
        trimSilence = defaults.object(forKey: Keys.trimSilence) as? Bool ?? true
        // Default OFF: Apple's VP-IO unit can suppress *all* mic input on an
        // input-only AVAudioEngine (no output render reference for its AEC),
        // which made Whisper hallucinate "Thank you" on the resulting silence.
        // Raw capture + GainNormalizer still delivers the whisper boost; VP-IO is
        // opt-in until its silent-capture failure mode is fully resolved.
        voiceProcessing = defaults.object(forKey: Keys.voiceProcessing) as? Bool ?? false
        ollamaModel = defaults.string(forKey: Keys.ollamaModel) ?? "llama3.2"
        groqModel = defaults.string(forKey: Keys.groqModel) ?? "llama-3.1-8b-instant"
        groqSmartModel = defaults.string(forKey: Keys.groqSmartModel) ?? "llama-3.3-70b-versatile"
        groqAPIKey = KeychainStore.get(.groqAPIKey) ?? ""
        launchAtLogin = SMAppService.mainApp.status == .enabled
        learnFromCorrections = defaults.bool(forKey: Keys.learnFromCorrections)
        let cmdRaw = defaults.string(forKey: Keys.commandModifier) ?? Hotkey.Modifier.rightOption.rawValue
        commandModifier = Hotkey.Modifier(rawValue: cmdRaw) ?? .rightOption
        commandModeEnabled = defaults.object(forKey: Keys.commandModeEnabled) as? Bool ?? true
    }

    var hotkey: Hotkey { Hotkey(kind: .modifier(hotkeyModifier)) }
    var commandHotkey: Hotkey { Hotkey(kind: .modifier(commandModifier)) }

    /// Turns on "launch at login" once, on first run — a menu-bar dictation app
    /// is meant to always be available, so it should come back after a reboot
    /// without the user relaunching it. Only applied a single time; if the user
    /// later disables it in Settings, that choice sticks.
    func applyDefaultLaunchAtLoginIfNeeded() {
        guard !defaults.bool(forKey: Keys.launchAtLoginDefaulted) else { return }
        defaults.set(true, forKey: Keys.launchAtLoginDefaulted)
        if SMAppService.mainApp.status != .enabled {
            launchAtLogin = true // didSet registers the login item
        }
    }

    /// One-time reset of the voice-processing preference to OFF. The first Phase 7
    /// build shipped it defaulting ON, which broke capture (silent mic → Whisper
    /// hallucinated "Thank you"). If a user had it persisted ON, flipping the code
    /// default alone wouldn't reach them — so force it off once. Runs a single
    /// time; a user can still turn it back on afterward and that choice sticks.
    func resetVoiceProcessingOnceIfNeeded() {
        guard !defaults.bool(forKey: Keys.voiceProcessingReset) else { return }
        defaults.set(true, forKey: Keys.voiceProcessingReset)
        if voiceProcessing { voiceProcessing = false } // didSet persists it
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            // Non-fatal; the toggle just won't stick.
        }
    }
}
