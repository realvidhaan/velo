import AppKit
import CoreGraphics
import os

/// Primary injector: writes text to the pasteboard and synthesizes ⌘V, then
/// restores the previous clipboard. This is what Wispr Flow does — it's fast,
/// layout-independent, and works in Electron/web views where AX injection fails.
public final class PasteInjector: TextInjector {
    private let log = Logger(subsystem: "com.flowclone.app", category: "Inject")
    private let pasteboard: NSPasteboard
    /// Delay before restoring the previous clipboard (lets the target app read ⌘V).
    private let restoreDelay: TimeInterval

    /// Marks our temporary clipboard write so clipboard managers (Maccy, Paste…)
    /// don't record it.
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    public init(pasteboard: NSPasteboard = .general, restoreDelay: TimeInterval = 0.3) {
        self.pasteboard = pasteboard
        self.restoreDelay = restoreDelay
    }

    public func inject(_ text: String) throws {
        guard !text.isEmpty else { throw InjectionError.empty }

        // Secure input field: can't paste into it. Leave text on the clipboard
        // (without restoring) so the user can paste manually, and report it.
        if SecureInputDetector.isEnabled {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            throw InjectionError.secureInputActive
        }
        guard Accessibility.isTrusted else {
            throw InjectionError.accessibilityNotGranted
        }

        let snapshot = PasteboardSnapshot.capture(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setString("1", forType: Self.transientType)
        let ourChangeCount = pasteboard.changeCount

        postCommandV()

        // Restore only if the user didn't copy something else in the meantime.
        // NSPasteboard is safe to touch on the main queue; the annotation just
        // opts out of the Sendable check for this known-safe capture.
        nonisolated(unsafe) let pb = pasteboard
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
            if pb.changeCount == ourChangeCount {
                snapshot.restore(to: pb)
            }
        }
    }

    private func postCommandV() {
        KeyEventPoster.post(keyCode: KeyEventPoster.vKeyCode, flags: .maskCommand)
    }
}
