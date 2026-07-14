import XCTest
import CoreGraphics
@testable import HotkeyService

final class HotkeyTests: XCTestCase {
    func testCodableRoundTripModifier() throws {
        let hk = Hotkey.fn
        let data = try JSONEncoder().encode(hk)
        let decoded = try JSONDecoder().decode(Hotkey.self, from: data)
        XCTAssertEqual(hk, decoded)
    }

    func testCodableRoundTripKeyWithModifiers() throws {
        let hk = Hotkey(kind: .key(keyCode: 105, modifiers: [.maskCommand, .maskShift]))
        let data = try JSONEncoder().encode(hk)
        let decoded = try JSONDecoder().decode(Hotkey.self, from: data)
        XCTAssertEqual(hk, decoded)
    }

    func testModifierFlagMasks() {
        XCTAssertEqual(Hotkey.Modifier.fn.flagMask, .maskSecondaryFn)
        XCTAssertEqual(Hotkey.Modifier.rightOption.flagMask, .maskAlternate)
    }

    func testPresetDisplayNames() {
        XCTAssertEqual(Hotkey.fn.displayName, "Fn (Globe)")
        XCTAssertEqual(Hotkey.f13.displayName, "F13")
    }

    func testCGEventFlagsCodable() throws {
        let flags: CGEventFlags = [.maskCommand, .maskAlternate]
        let data = try JSONEncoder().encode(flags)
        let decoded = try JSONDecoder().decode(CGEventFlags.self, from: data)
        XCTAssertEqual(flags, decoded)
    }
}
