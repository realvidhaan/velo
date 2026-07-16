import SwiftUI
import AppKit
import IndicatorUI

/// Owns a borderless, non-activating floating `NSPanel` that hosts the SwiftUI
/// recording indicator. The panel floats above all apps and spaces and never
/// steals focus, so dictation into the focused app is unaffected.
@MainActor
final class IndicatorController {
    let model = IndicatorModel()
    private var panel: NSPanel?

    func show(_ state: IndicatorState) {
        model.state = state
        ensurePanel()
        reposition()
        panel?.orderFrontRegardless()
    }

    func update(level: Float) {
        model.level = level
    }

    func setState(_ state: IndicatorState) {
        model.state = state
    }

    func hide() {
        model.state = .hidden
        model.level = 0
        panel?.orderOut(nil)
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 44),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: IndicatorView(model: model))
        self.panel = panel
    }

    private func reposition() {
        guard let panel, let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        let x = visible.midX - size.width / 2
        let y = visible.minY + 80
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
