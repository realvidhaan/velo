import CoreGraphics

/// Posts synthetic keystrokes — the single place Velo emits keyboard
/// events (⌘V for paste injection, ⌘C for reading a selection).
public enum KeyEventPoster {
    /// Common virtual key codes.
    public static let cKeyCode: CGKeyCode = 0x08
    public static let vKeyCode: CGKeyCode = 0x09

    /// Synthesizes a key down + up with the given modifier flags.
    public static func post(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        // Build both events up front so we never post a lone key-down (leaving a
        // modifier stuck) when the key-up can't be created.
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
