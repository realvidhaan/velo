import Foundation

/// Which flavor of session is running. Dictation is v1; command is v2 (Command Mode).
public enum SessionMode: Sendable, Equatable {
    case dictation
    case command
}

/// The lifecycle of a single utterance. This is a pure value type with no
/// dependencies on AppKit/audio so it can be exhaustively unit-tested.
///
/// Happy path: `idle → recording → transcribing → cleaning → injecting → idle`.
/// Every failure degrades to `error` (surfaced briefly) and then back to `idle`,
/// so the machine has no dead ends.
public enum DictationState: Sendable, Equatable {
    case idle
    case recording(SessionMode)
    case transcribing(SessionMode)
    case cleaning(SessionMode, raw: String)
    case injecting(SessionMode, text: String)
    /// Transient: a message is shown on the indicator, then the controller
    /// drives `.reset` back to `.idle`.
    case error(String)

    public var isBusy: Bool {
        if case .idle = self { return false }
        if case .error = self { return false }
        return true
    }

    public var mode: SessionMode? {
        switch self {
        case .recording(let m), .transcribing(let m): return m
        case .cleaning(let m, _), .injecting(let m, _): return m
        case .idle, .error: return nil
        }
    }
}

/// Inputs that drive the state machine.
public enum DictationEvent: Sendable, Equatable {
    case hotkeyDown(SessionMode)
    case hotkeyUp
    /// STT produced a final transcript (may be empty).
    case transcriptFinalized(String)
    /// Cleanup pass finished (or fell back to raw).
    case cleaned(String)
    /// Text was successfully injected at the cursor.
    case injected
    /// User cancelled (Esc, or used the hotkey as a modifier).
    case cancel
    /// Any stage failed; carries a user-facing message.
    case failed(String)
    /// Controller acknowledges the transient error/injection and returns to idle.
    case reset
}

public enum DictationStateMachine {
    /// Pure transition. Unknown (state, event) pairs are no-ops that return the
    /// current state unchanged — this keeps overlapping hotkey presses and
    /// stray events harmless.
    public static func reduce(_ state: DictationState, _ event: DictationEvent) -> DictationState {
        switch (state, event) {
        // Start recording only from idle (overlapping presses while busy are ignored).
        case (.idle, .hotkeyDown(let mode)):
            return .recording(mode)

        // Release the key → finalize STT.
        case (.recording(let mode), .hotkeyUp):
            return .transcribing(mode)

        // Empty transcript is treated as nothing-to-do.
        case (.transcribing, .transcriptFinalized(let text)) where text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            return .idle
        case (.transcribing(let mode), .transcriptFinalized(let text)):
            return .cleaning(mode, raw: text)

        case (.cleaning(let mode, _), .cleaned(let text)):
            return .injecting(mode, text: text)

        case (.injecting, .injected):
            return .idle

        // Cancellation from any active state.
        case (_, .cancel) where state.isBusy:
            return .idle

        // Any stage failure surfaces a transient error.
        case (_, .failed(let message)) where state.isBusy:
            return .error(message)

        // Controller clears the transient error.
        case (.error, .reset):
            return .idle

        // Everything else is a no-op (e.g. hotkeyDown while busy, hotkeyUp when idle).
        default:
            return state
        }
    }
}
