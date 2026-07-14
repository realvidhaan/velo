import ApplicationServices
import AppKit

/// Reads the text value of the currently focused UI element via the
/// Accessibility API. Used to detect user edits (correction capture) and, in
/// Command Mode (v2), to read the current selection. Best-effort: returns nil in
/// apps that don't expose AX values (some Electron/web views).
public enum FocusedFieldReader {
    /// The full text value of the focused element, if available.
    public static func focusedText() -> String? {
        guard Accessibility.isTrusted else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else {
            return nil
        }
        let axElement = element as! AXUIElement
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &value) == .success,
              let string = value as? String else {
            return nil
        }
        return string
    }

    /// The selected text of the focused element, if available (for Command Mode).
    public static func selectedText() -> String? {
        guard Accessibility.isTrusted else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else {
            return nil
        }
        let axElement = element as! AXUIElement
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axElement, kAXSelectedTextAttribute as CFString, &value) == .success,
              let string = value as? String, !string.isEmpty else {
            return nil
        }
        return string
    }
}
