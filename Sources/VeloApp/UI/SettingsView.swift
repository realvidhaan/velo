import SwiftUI
import HotkeyService
import PersistenceKit
import SettingsUI

struct SettingsView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        TabView {
            GeneralSettingsView(controller: controller)
                .tabItem { Label("General", systemImage: "gearshape") }
            DictionarySettingsView(dataStore: controller.dataStore)
                .tabItem { Label("Dictionary", systemImage: "character.book.closed") }
            ReplacementRulesSettingsView(dataStore: controller.dataStore)
                .tabItem { Label("Your Voice", systemImage: "wand.and.stars") }
            AppProfilesSettingsView(dataStore: controller.dataStore)
                .tabItem { Label("App Formatting", systemImage: "app.badge") }
            HistorySettingsView(dataStore: controller.dataStore)
                .tabItem { Label("History", systemImage: "clock") }
        }
        .frame(width: 520, height: 420)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject private var settings: SettingsStore

    init(controller: AppController) {
        self.controller = controller
        self.settings = controller.settings
    }

    var body: some View {
        Form {
            Section("Hotkey") {
                Picker("Hold to dictate", selection: $settings.hotkeyModifier) {
                    ForEach(Hotkey.Modifier.allCases, id: \.self) { mod in
                        Text(mod.displayName).tag(mod)
                    }
                }
                .onChange(of: settings.hotkeyModifier) { _, _ in
                    controller.applyHotkeySetting()
                }
                if settings.hotkeyModifier == .fn {
                    Text("Set the Globe/Fn key to “Do Nothing” in System Settings ▸ Keyboard so it doesn't trigger dictation or emoji.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Command Mode") {
                Toggle("Enable Command Mode", isOn: $settings.commandModeEnabled)
                    .onChange(of: settings.commandModeEnabled) { _, _ in controller.applyCommandModeSetting() }
                if settings.commandModeEnabled {
                    Picker("Command hotkey", selection: $settings.commandModifier) {
                        ForEach(Hotkey.Modifier.allCases, id: \.self) { mod in
                            Text(mod.displayName).tag(mod)
                        }
                    }
                    .onChange(of: settings.commandModifier) { _, _ in controller.applyHotkeySetting() }
                    Text("Select text, hold this key, speak an instruction (e.g. “make this more formal”), and the selection is replaced.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Speech recognition") {
                Picker("Engine", selection: $settings.sttChoice) {
                    ForEach(SettingsStore.STTChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                if settings.sttChoice == .groqWhisper || settings.sttChoice == .auto {
                    SecureField("Groq API key", text: $settings.groqAPIKey)
                    Text("Free key at console.groq.com. Audio is sent to Groq for transcription.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if settings.sttChoice == .whisperKit || settings.sttChoice == .auto {
                    whisperKitModelRow
                }
                Toggle("Trim silence before transcription", isOn: $settings.trimSilence)
                Text("Removes dead air at the start and end of each recording — fewer misfires, faster results.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Extra noise suppression (experimental)", isOn: $settings.voiceProcessing)
                Text("Routes the mic through Apple's voice processing to suppress background noise. Experimental: on some Macs it can mute the mic entirely, so it's off by default. Whisper boosting works regardless of this setting. Takes effect on your next dictation.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Cleanup engine") {
                Picker("Engine", selection: $settings.cleanupChoice) {
                    ForEach(SettingsStore.CleanupChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                if settings.cleanupChoice == .groq || settings.cleanupChoice == .auto {
                    SecureField("Groq API key", text: $settings.groqAPIKey)
                    TextField("Fast model (every dictation)", text: $settings.groqModel)
                    TextField("Smart model (lists, email, long or difficult text)", text: $settings.groqSmartModel)
                    Text("Free key at console.groq.com. Every dictation is cleaned with the fast model; reformatting, long phrases, and Command Mode use the smart model.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if settings.cleanupChoice == .ollama {
                    TextField("Ollama model", text: $settings.ollamaModel)
                    Text("Requires Ollama running locally. Fully private.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Learn from my corrections", isOn: $settings.learnFromCorrections)
                if settings.learnFromCorrections {
                    Text("When you edit dictated text, Velo notices recurring fixes and offers to add them to your dictionary. It reads the focused field to do this.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Permissions") {
                LabeledContent("Hotkey (Input Monitoring)") {
                    Text(controller.hotkeyActive ? "Granted" : "Not granted")
                        .foregroundStyle(controller.hotkeyActive ? .green : .orange)
                }
                LabeledContent("Insert text (Accessibility)") {
                    Text(controller.accessibilityGranted ? "Granted" : "Not granted")
                        .foregroundStyle(controller.accessibilityGranted ? .green : .orange)
                }
                if !controller.accessibilityGranted {
                    Button("Grant Accessibility…") { controller.requestAccessibility() }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Download / status control for the on-device WhisperKit model. Kept opt-in
    /// (never auto-downloads) since the model is ~600 MB.
    @ViewBuilder private var whisperKitModelRow: some View {
        if controller.whisperKitInstalled {
            LabeledContent("On-device model") {
                Text("Installed").foregroundStyle(.green)
            }
        } else if controller.whisperKitDownloading {
            LabeledContent("On-device model") {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Downloading…").foregroundStyle(.secondary)
                }
            }
        } else {
            Button("Download on-device model (~600 MB)") {
                controller.downloadWhisperKitModel()
            }
            Text("Runs Whisper fully offline on the Neural Engine. One-time download.")
                .font(.caption).foregroundStyle(.secondary)
        }
        if let error = controller.whisperKitError {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }
}
