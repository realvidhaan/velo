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
        static let learnFromCorrections = "learning.enabled"
        static let hasCompletedOnboarding = "onboarding.completed"
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

    @Published var hotkeyModifier: Hotkey.Modifier {
        didSet { defaults.set(hotkeyModifier.rawValue, forKey: Keys.hotkeyModifier) }
    }
    @Published var cleanupChoice: CleanupChoice {
        didSet { defaults.set(cleanupChoice.rawValue, forKey: Keys.cleanupEngine) }
    }
    @Published var ollamaModel: String {
        didSet { defaults.set(ollamaModel, forKey: Keys.ollamaModel) }
    }
    @Published var groqModel: String {
        didSet { defaults.set(groqModel, forKey: Keys.groqModel) }
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

    init() {
        let modRaw = defaults.string(forKey: Keys.hotkeyModifier) ?? Hotkey.Modifier.fn.rawValue
        hotkeyModifier = Hotkey.Modifier(rawValue: modRaw) ?? .fn
        let choiceRaw = defaults.string(forKey: Keys.cleanupEngine) ?? CleanupChoice.auto.rawValue
        cleanupChoice = CleanupChoice(rawValue: choiceRaw) ?? .auto
        ollamaModel = defaults.string(forKey: Keys.ollamaModel) ?? "llama3.2"
        groqModel = defaults.string(forKey: Keys.groqModel) ?? "llama-3.1-8b-instant"
        groqAPIKey = KeychainStore.get(.groqAPIKey) ?? ""
        launchAtLogin = SMAppService.mainApp.status == .enabled
        learnFromCorrections = defaults.bool(forKey: Keys.learnFromCorrections)
    }

    var hotkey: Hotkey { Hotkey(kind: .modifier(hotkeyModifier)) }

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
