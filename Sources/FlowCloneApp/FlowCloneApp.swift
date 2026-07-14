import SwiftUI
import AppKit
import FlowCore

/// FlowClone is a menu-bar-only (`LSUIElement`) app. There is no main window;
/// the entire UI lives in the menu bar item, a floating recording indicator,
/// and (later) a Settings scene.
@main
struct FlowCloneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("FlowClone", systemImage: "mic.fill") {
            MenuBarContentView(controller: delegate.controller)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Owns the runtime controller and starts services once the app has launched
/// (rather than lazily when the menu is first opened).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.startServices()
    }
}
