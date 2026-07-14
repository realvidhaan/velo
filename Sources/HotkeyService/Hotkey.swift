import Foundation
import CoreGraphics

/// A hold-to-talk hotkey. Two flavors:
///
/// - `.modifier` — a modifier key held on its own (Fn/Globe, Right Option…).
///   Detected via `flagsChanged` events; the corresponding flag bit tells us
///   whether it is currently down.
/// - `.key` — a regular key (e.g. F13), optionally with modifiers. Detected via
///   `keyDown`/`keyUp`; the event tap swallows these so the key doesn't type
///   into the focused app while held.
public struct Hotkey: Codable, Equatable, Sendable {
    public enum Kind: Codable, Equatable, Sendable {
        case modifier(Modifier)
        case key(keyCode: Int64, modifiers: Modifier.Set)
    }

    public var kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }

    /// A modifier that can be held on its own as a push-to-talk key.
    public enum Modifier: String, Codable, Equatable, Sendable, CaseIterable {
        case fn            // Fn / Globe (keyCode 63)
        case rightOption
        case rightCommand
        case rightControl

        /// The `CGEventFlags` bit that is set while this modifier is held.
        public var flagMask: CGEventFlags {
            switch self {
            case .fn: return .maskSecondaryFn
            case .rightOption: return .maskAlternate
            case .rightCommand: return .maskCommand
            case .rightControl: return .maskControl
            }
        }

        public var displayName: String {
            switch self {
            case .fn: return "Fn (Globe)"
            case .rightOption: return "Right Option"
            case .rightCommand: return "Right Command"
            case .rightControl: return "Right Control"
            }
        }

        /// A `CGEventFlags` OptionSet alias so `.key` can carry required modifiers.
        public typealias Set = CGEventFlags
    }

    // MARK: Presets

    public static let fn = Hotkey(kind: .modifier(.fn))
    public static let rightOption = Hotkey(kind: .modifier(.rightOption))
    /// F13 has keyCode 105 and no default system binding — a safe non-modifier default.
    public static let f13 = Hotkey(kind: .key(keyCode: 105, modifiers: []))

    public var displayName: String {
        switch kind {
        case .modifier(let m): return m.displayName
        case .key(let code, _): return keyName(for: code)
        }
    }
}

// CGEventFlags is a bit set of modifier flags; make it Codable for persistence.
extension CGEventFlags: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(UInt64.self)
        self.init(rawValue: raw)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

private func keyName(for keyCode: Int64) -> String {
    switch keyCode {
    case 105: return "F13"
    case 107: return "F14"
    case 113: return "F15"
    case 63: return "Fn"
    default: return "Key \(keyCode)"
    }
}
