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

            Section("Cleanup engine") {
                Picker("Engine", selection: $settings.cleanupChoice) {
                    ForEach(SettingsStore.CleanupChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                if settings.cleanupChoice == .groq || settings.cleanupChoice == .auto {
                    SecureField("Groq API key", text: $settings.groqAPIKey)
                    TextField("Groq model", text: $settings.groqModel)
                    Text("Free key at console.groq.com. Transcript text is sent to Groq for cleanup.")
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
                    Text("When you edit dictated text, FlowClone notices recurring fixes and offers to add them to your dictionary. It reads the focused field to do this.")
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
}
