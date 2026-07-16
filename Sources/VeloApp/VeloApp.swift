import SwiftUI
import AppKit
import FlowCore
import PersistenceKit

/// Velo is a menu-bar-only (`LSUIElement`) app. There is no main window;
/// the UI lives in the menu bar item, a floating recording indicator, and a
/// Settings window (dictionary, per-app formatting, history, engines).
@main
struct VeloApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Velo", systemImage: "mic.fill") {
            MenuBarContentView(controller: delegate.controller)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(controller: delegate.controller)
        }
    }
}

/// Owns the stores and runtime controller; starts services after launch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller: AppController
    private lazy var onboarding = OnboardingWindowController(controller: controller)

    override init() {
        // A failure here means persistence is unavailable; fall back to an
        // in-memory store so the core dictation still works.
        let dataStore = (try? DataStore()) ?? (try! DataStore(inMemory: true))
        let settings = SettingsStore()
        self.controller = AppController(dataStore: dataStore, settings: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Default to launching at login so the app is always available (survives
        // reboots); one-time, and the user can turn it off in Settings.
        controller.settings.applyDefaultLaunchAtLoginIfNeeded()
        // Undo the broken Phase 7 default (VP-IO ON → silent capture) for anyone
        // who already ran that build.
        controller.settings.resetVoiceProcessingOnceIfNeeded()
        controller.startServices()
        onboarding.showIfNeeded()
    }

    func showOnboarding() {
        onboarding.show()
    }
}
