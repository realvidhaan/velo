import Foundation
import IOKit.hid
import os

/// Manages the global hold-to-talk hotkey: Input Monitoring permission plus the
/// underlying `EventTap`. Higher layers (the app's controller) subscribe to
/// `onEvent` and apply their own debounce / state-machine logic.
@MainActor
public final class HotkeyService {
    private let log = Logger(subsystem: "com.flowclone.app", category: "HotkeyService")

    public private(set) var hotkey: Hotkey
    /// Called on the main actor for every hotkey down/up/cancel.
    public var onEvent: ((HotkeyEvent) -> Void)?

    private var tap: EventTap?

    public init(hotkey: Hotkey = .fn) {
        self.hotkey = hotkey
    }

    // MARK: Permission (Input Monitoring)

    public enum PermissionStatus {
        case granted, denied, undetermined
    }

    public static var inputMonitoringStatus: PermissionStatus {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied: return .denied
        default: return .undetermined
        }
    }

    /// Prompts for Input Monitoring if not yet determined. Returns whether it is
    /// already granted (the prompt is asynchronous; poll `inputMonitoringStatus`).
    @discardableResult
    public static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    // MARK: Lifecycle

    /// Starts the tap. Returns whether it started (false ⇒ grant Input Monitoring).
    @discardableResult
    public func start() -> Bool {
        let tap = EventTap(hotkey: hotkey) { [weak self] event in
            // EventTap guarantees delivery on the main queue, so we can assume
            // main-actor isolation to reach `onEvent`.
            MainActor.assumeIsolated {
                self?.onEvent?(event)
            }
        }
        let ok = tap.start()
        self.tap = ok ? tap : nil
        if !ok { log.error("Hotkey tap failed to start") }
        return ok
    }

    public func stop() {
        tap?.stop()
        tap = nil
    }

    public func update(hotkey newValue: Hotkey) {
        hotkey = newValue
        tap?.updateHotkey(newValue)
    }
}
