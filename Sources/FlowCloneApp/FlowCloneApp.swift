import SwiftUI
import FlowCore

/// FlowClone is a menu-bar-only (`LSUIElement`) app. There is no main window;
/// the entire UI lives in the menu bar item and (later) a Settings scene plus a
/// floating recording indicator panel.
@main
struct FlowCloneApp: App {
    var body: some Scene {
        MenuBarExtra("FlowClone", systemImage: "mic.fill") {
            MenuBarContentView()
        }
        .menuBarExtraStyle(.menu)
    }
}
