import Foundation
import CoreGraphics
import os

/// What the tap observed about the configured hotkey.
public enum HotkeyEvent: Sendable {
    case down
    case up
    /// User pressed Esc, or pressed another key while a modifier hotkey was held
    /// (i.e. they were using it as a real modifier) — the session should cancel.
    case cancel
}

/// A low-level active `CGEventTap` that detects a single configured hotkey and
/// reports down/up/cancel. Runs its tap on a dedicated thread with its own
/// run loop so it is never starved by the main thread.
///
/// Requires **Input Monitoring** (and Accessibility for injection elsewhere).
/// `start()` returns `false` if the tap could not be created — almost always
/// because Input Monitoring has not been granted yet.
public final class EventTap: @unchecked Sendable {
    private let log = Logger(subsystem: "com.flowclone.app", category: "EventTap")

    private var hotkey: Hotkey
    private let handler: @Sendable (HotkeyEvent) -> Void

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var thread: Thread?
    private var threadRunLoop: CFRunLoop?

    /// Whether the modifier hotkey is currently held (modifier flavor only).
    private var modifierHeld = false

    private static let escKeyCode: Int64 = 53

    public init(hotkey: Hotkey, handler: @escaping @Sendable (HotkeyEvent) -> Void) {
        self.hotkey = hotkey
        self.handler = handler
    }

    public func updateHotkey(_ newValue: Hotkey) {
        hotkey = newValue
        modifierHeld = false
    }

    // MARK: Lifecycle

    /// Creates the tap and spins up its run loop thread. Returns whether the tap
    /// was successfully created (false ⇒ Input Monitoring not granted).
    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            log.error("CGEvent.tapCreate failed — Input Monitoring likely not granted")
            return false
        }
        self.tap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source

        let thread = Thread { [weak self] in
            // Read the non-Sendable CF objects off `self` inside the thread body
            // rather than capturing them directly in this @Sendable closure.
            guard let self, let source = self.runLoopSource, let tap = self.tap else { return }
            let rl = CFRunLoopGetCurrent()
            self.threadRunLoop = rl
            CFRunLoopAddSource(rl, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "com.flowclone.EventTap"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
        log.info("Event tap started for hotkey \(self.hotkey.displayName, privacy: .public)")
        return true
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let rl = threadRunLoop, let source = runLoopSource {
            CFRunLoopRemoveSource(rl, source, .commonModes)
            CFRunLoopStop(rl)
        }
        tap = nil
        runLoopSource = nil
        thread = nil
        threadRunLoop = nil
        modifierHeld = false
    }

    // MARK: Callback

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The tap gets disabled if our callback is too slow or on user input
        // during a debugger pause. Re-enable it immediately and pass through.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        switch hotkey.kind {
        case .modifier(let modifier):
            return handleModifier(modifier, type: type, event: event)
        case .key(let keyCode, let modifiers):
            return handleKey(keyCode: keyCode, requiredModifiers: modifiers, type: type, event: event)
        }
    }

    private func handleModifier(_ modifier: Hotkey.Modifier, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .flagsChanged {
            let isSet = event.flags.contains(modifier.flagMask)
            if isSet && !modifierHeld {
                modifierHeld = true
                emit(.down)
            } else if !isSet && modifierHeld {
                modifierHeld = false
                emit(.up)
            }
            // Pass modifier events through so normal modifier behavior is intact.
            return Unmanaged.passUnretained(event)
        }

        // A regular key pressed while the modifier hotkey is held → the user is
        // using it as a real modifier (or pressed Esc). Cancel the session; pass
        // the key through.
        if type == .keyDown, modifierHeld {
            emit(.cancel)
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleKey(keyCode: Int64, requiredModifiers: CGEventFlags, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let code = event.getIntegerValueField(.keyboardEventKeycode)

        // Esc always means cancel (not swallowed — apps expect Esc).
        if type == .keyDown, code == Self.escKeyCode {
            emit(.cancel)
            return Unmanaged.passUnretained(event)
        }

        guard code == keyCode else { return Unmanaged.passUnretained(event) }

        // Check required modifiers (ignore caps lock / independent bits).
        let relevant: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
        if !requiredModifiers.isEmpty {
            let masked = event.flags.intersection(relevant)
            guard masked == requiredModifiers.intersection(relevant) else {
                return Unmanaged.passUnretained(event)
            }
        }

        switch type {
        case .keyDown:
            emit(.down)   // covers auto-repeat too; controller ignores repeats while busy
            return nil    // swallow so the key doesn't type into the focused app
        case .keyUp:
            emit(.up)
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func emit(_ event: HotkeyEvent) {
        let handler = self.handler
        DispatchQueue.main.async { handler(event) }
    }
}
