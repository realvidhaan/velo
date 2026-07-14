import SwiftUI
import FlowCore

struct MenuBarContentView: View {
    var body: some View {
        Text("FlowClone \(FlowCloneInfo.version)")
        Divider()
        Text("Hold-to-talk dictation")
            .foregroundStyle(.secondary)
        Divider()
        Button("Quit FlowClone") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
