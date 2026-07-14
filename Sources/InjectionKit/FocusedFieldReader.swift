import ApplicationServices
import AppKit

/// Reads the text value of the currently focused UI element via the
/// Accessibility API. Used to detect user edits (correction capture) and, in
/// Command Mode (v2), to read the current selection. Best-effort: returns nil in
/// apps that don't expose AX values (some Electron/web views).
public enum FocusedFieldReader {
    /// The full text value of the focused element, if available.
    public static func focusedText() -> String? {
        stringAttribute(kAXValueAttribute)
    }

    /// The selected text of the focused element, if available (for Command Mode).
    public static func selectedText() -> String? {
        guard let selected = stringAttribute(kAXSelectedTextAttribute), !selected.isEmpty else { return nil }
        return selected
    }

    /// Walks to the system-wide focused UI element and copies a string attribute.
    private static func stringAttribute(_ attribute: String) -> String? {
        guard Accessibility.isTrusted else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else {
            return nil
        }
        let axElement = element as! AXUIElement
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axElement, attribute as CFString, &value) == .success,
              let string = value as? String else {
            return nil
        }
        return string
    }
}
