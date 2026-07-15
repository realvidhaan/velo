import XCTest
@testable import CleanupKit

final class ReplacementRulesTests: XCTestCase {
    func testAppliesSimpleSubstitution() {
        let out = ReplacementRules.apply(
            "i love get hub",
            rules: [Replacement(originals: ["get hub"], replacement: "GitHub")]
        )
        XCTAssertEqual(out, "i love GitHub")
    }

    func testCaseInsensitiveMatch() {
        let out = ReplacementRules.apply(
            "Vidon shipped it",
            rules: [Replacement(originals: ["vidon"], replacement: "Vidhaan")]
        )
        XCTAssertEqual(out, "Vidhaan shipped it")
    }

    func testWordBoundaryDoesNotMatchInsideWord() {
        // "cat" must not hit "category".
        let out = ReplacementRules.apply(
            "the category is set",
            rules: [Replacement(originals: ["cat"], replacement: "DOG")]
        )
        XCTAssertEqual(out, "the category is set")
    }

    func testMultipleVariantsMapToOneCanonical() {
        let rule = Replacement(originals: ["voicing", "voice ink", "voiceing"], replacement: "VoiceInk")
        XCTAssertEqual(ReplacementRules.apply("i use voicing daily", rules: [rule]), "i use VoiceInk daily")
        XCTAssertEqual(ReplacementRules.apply("open voice ink now", rules: [rule]), "open VoiceInk now")
    }

    func testLongestPatternAppliedFirst() {
        // "new york city" should win over "new york".
        let rules = [
            Replacement(originals: ["new york"], replacement: "NY"),
            Replacement(originals: ["new york city"], replacement: "NYC"),
        ]
        XCTAssertEqual(ReplacementRules.apply("i live in new york city", rules: rules), "i live in NYC")
    }

    func testEmptyInputsAreNoOps() {
        XCTAssertEqual(ReplacementRules.apply("", rules: [Replacement(originals: ["x"], replacement: "y")]), "")
        XCTAssertEqual(ReplacementRules.apply("hello", rules: []), "hello")
    }

    func testBlankOriginalsIgnored() {
        let out = ReplacementRules.apply(
            "keep me",
            rules: [Replacement(originals: ["  "], replacement: "GONE")]
        )
        XCTAssertEqual(out, "keep me")
    }
}
