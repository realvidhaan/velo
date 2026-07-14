import SwiftUI
import FlowCore
import HotkeyService
import LearningKit

struct MenuBarContentView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        Text("FlowClone \(FlowCloneInfo.version)")

        Divider()

        if controller.hotkeyActive {
            Text("Hold Fn to dictate")
                .foregroundStyle(.secondary)
        } else {
            Text("⚠︎ Input Monitoring not granted")
                .foregroundStyle(.secondary)
            Button("Open Input Monitoring settings…") {
                openInputMonitoringSettings()
            }
            Button("Retry hotkey") {
                controller.retryHotkey()
            }
        }

        if !controller.accessibilityGranted {
            Divider()
            Text("⚠︎ Accessibility needed to insert text")
                .foregroundStyle(.secondary)
            Button("Grant Accessibility…") {
                controller.requestAccessibility()
            }
        }

        if let suggestion = controller.pendingSuggestion {
            Divider()
            Text("Add “\(suggestion.from)” → “\(suggestion.to)” to dictionary?")
                .foregroundStyle(.secondary)
            Button("Add to dictionary") { controller.acceptSuggestion() }
            Button("Dismiss") { controller.dismissSuggestion() }
        }

        if !controller.lastTranscript.isEmpty {
            Divider()
            Text("Last: \(controller.lastTranscript)")
                .foregroundStyle(.secondary)
        }

        Divider()

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")

        Button("Setup Guide…") {
            (NSApp.delegate as? AppDelegate)?.showOnboarding()
        }

        Button("Quit FlowClone") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }
}
