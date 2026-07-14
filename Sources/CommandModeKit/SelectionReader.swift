import AppKit
import CoreGraphics
import InjectionKit

/// Reads the currently selected text for Command Mode. Prefers the Accessibility
/// value (`kAXSelectedText`); falls back to synthesizing ⌘C and reading the
/// pasteboard (restoring it afterward) for apps that don't expose AX selection.
public enum SelectionReader {
    /// The current selection, or nil if nothing is selected / can't be read.
    public static func read() -> String? {
        if let ax = FocusedFieldReader.selectedText(), !ax.isEmpty {
            return ax
        }
        return readViaCopy()
    }

    private static func readViaCopy() -> String? {
        guard Accessibility.isTrusted else { return nil }
        let pb = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(pb)
        let beforeCount = pb.changeCount

        KeyEventPoster.post(keyCode: KeyEventPoster.cKeyCode, flags: .maskCommand)

        // Give the target app a moment to service the copy.
        let deadline = Date().addingTimeInterval(0.3)
        while pb.changeCount == beforeCount && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }

        let copied = (pb.changeCount != beforeCount) ? pb.string(forType: .string) : nil
        snapshot.restore(to: pb)
        guard let copied, !copied.isEmpty else { return nil }
        return copied
    }
}
