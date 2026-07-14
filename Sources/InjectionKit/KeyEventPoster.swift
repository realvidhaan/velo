import CoreGraphics

/// Posts synthetic keystrokes — the single place FlowClone emits keyboard
/// events (⌘V for paste injection, ⌘C for reading a selection).
public enum KeyEventPoster {
    /// Common virtual key codes.
    public static let cKeyCode: CGKeyCode = 0x08
    public static let vKeyCode: CGKeyCode = 0x09

    /// Synthesizes a key down + up with the given modifier flags.
    public static func post(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
