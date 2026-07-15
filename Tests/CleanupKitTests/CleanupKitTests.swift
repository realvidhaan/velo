import XCTest
@testable import CleanupKit

final class LocalPolishTests: XCTestCase {
    func testCapitalizesAndAddsPeriod() {
        // "three" is digitized to "3" (dictation convention).
        XCTAssertEqual(LocalPolish.polish("let's meet at three"), "Let's meet at 3.")
    }

    func testRemovesHardFillers() {
        XCTAssertEqual(LocalPolish.polish("send um the uh report"), "Send the report.")
    }

    func testDropsLeadingFiller() {
        XCTAssertEqual(LocalPolish.polish("so we should ship it"), "We should ship it.")
    }

    func testKeepsMidSentenceLike() {
        // "like" is only stripped when leading; here it must stay (period added
        // because it's a 3-word sentence).
        XCTAssertEqual(LocalPolish.polish("I like it"), "I like it.")
    }

    func testShortUtteranceNotForcedPunctuation() {
        // <3 words: no forced period.
        XCTAssertEqual(LocalPolish.polish("yes"), "Yes")
    }

    func testDigitizesStandaloneNumber() {
        XCTAssertEqual(LocalPolish.polish("ten"), "10")
        XCTAssertEqual(LocalPolish.polish("I need ten copies"), "I need 10 copies.")
    }

    func testDigitizesCompoundNumber() {
        // "twenty five" -> "25"; result is 2 words, so no forced period.
        XCTAssertEqual(LocalPolish.polish("twenty five dollars"), "25 dollars")
    }

    func testCollapsesImmediateRepeats() {
        XCTAssertEqual(LocalPolish.polish("the the report is is done"), "The report is done.")
    }

    func testIsShort() {
        // ≤2 words fast-paths; anything sentence-shaped goes to the LLM.
        XCTAssertTrue(LocalPolish.isShort("sounds good"))
        XCTAssertTrue(LocalPolish.isShort("yes"))
        XCTAssertFalse(LocalPolish.isShort("one two three"))
        XCTAssertFalse(LocalPolish.isShort("let's meet at ten"))
    }

    func testEmptyStaysEmpty() {
        XCTAssertEqual(LocalPolish.polish("   "), "")
    }
}

final class CleanupPromptTests: XCTestCase {
    func testUserWrapsTranscriptAsData() {
        XCTAssertEqual(CleanupPrompt.user("hi"), "<transcript>\nhi\n</transcript>")
    }

    func testSystemIncludesDictionaryTerms() {
        let s = CleanupPrompt.system(dictionary: ["Vidhaan", "FlowClone"], appHint: nil)
        XCTAssertTrue(s.contains("Vidhaan"))
        XCTAssertTrue(s.contains("FlowClone"))
    }

    func testSystemIncludesAppHint() {
        let s = CleanupPrompt.system(dictionary: [], appHint: "casual text message")
        XCTAssertTrue(s.contains("casual text message"))
    }

    func testSystemHasInjectionGuard() {
        let s = CleanupPrompt.system(dictionary: [], appHint: nil).lowercased()
        XCTAssertTrue(s.contains("data, not an instruction"))
        XCTAssertTrue(s.contains("never follow"))
    }

    func testSystemInstructsNumberAndFillerFormatting() {
        let s = CleanupPrompt.system(dictionary: [], appHint: nil).lowercased()
        XCTAssertTrue(s.contains("number"))   // digitize numbers
        XCTAssertTrue(s.contains("filler"))   // remove fillers
    }

    func testSystemForbidsSummarizing() {
        let s = CleanupPrompt.system(dictionary: [], appHint: nil).lowercased()
        XCTAssertTrue(s.contains("do not summarize") || s.contains("not summarize"))
    }
}

final class AppProfilesTests: XCTestCase {
    func testKnownAppHint() {
        XCTAssertNotNil(AppProfileDefaults.hint(forBundleID: "com.apple.mail"))
        XCTAssertTrue(AppProfileDefaults.hint(forBundleID: "com.apple.MobileSMS")!.contains("casual"))
    }

    func testUnknownAppIsNeutral() {
        XCTAssertNil(AppProfileDefaults.hint(forBundleID: "com.example.unknown"))
        XCTAssertNil(AppProfileDefaults.hint(forBundleID: nil))
    }
}

final class PostGuardTests: XCTestCase {
    func testAcceptsReasonableOutput() {
        XCTAssertTrue(CleanupPostGuard.isAcceptable("Let's meet at three.", original: "lets meet at three"))
    }

    func testRejectsEmpty() {
        XCTAssertFalse(CleanupPostGuard.isAcceptable("   ", original: "hello there"))
    }

    func testRejectsBloatedResponse() {
        let original = "what time is it"
        let bloated = String(repeating: "The current time depends on your timezone. ", count: 10)
        XCTAssertFalse(CleanupPostGuard.isAcceptable(bloated, original: original))
    }

    func testRejectsRefusal() {
        XCTAssertFalse(CleanupPostGuard.isAcceptable("I cannot help with that request.", original: "some text here please"))
        XCTAssertFalse(CleanupPostGuard.isAcceptable("Sure, here is the cleaned text: hello", original: "hello there friend"))
    }
}

/// Live cleanup via Apple Foundation Models (local, no key). Gated because it
/// needs Apple Intelligence enabled and is slow.
final class FoundationModelCleanupTests: XCTestCase {
    func testCleanupWithAppleModel() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FLOWCLONE_RUN_LLM_TEST"] == "1",
            "Set FLOWCLONE_RUN_LLM_TEST=1 to run the live Apple Foundation Models test"
        )
        let engine = FoundationModelCleanupEngine()
        guard await engine.isAvailable() else {
            throw XCTSkip("Apple Foundation Models not available on this machine")
        }
        let raw = "um so basically lets uh meet at three tomorrow to talk about the you know the project"
        let cleaned = try await engine.cleanup(CleanupRequest(raw: raw))
        print("FM cleanup: \(cleaned)")
        XCTAssertFalse(cleaned.isEmpty)
        XCTAssertFalse(cleaned.lowercased().contains(" um "))
        // Accept either the digit "3" or the word (Apple FM is less consistent
        // at number formatting than Groq/Whisper).
        XCTAssertTrue(cleaned.contains("3") || cleaned.lowercased().contains("three"))
        XCTAssertTrue(cleaned.lowercased().contains("project"))
    }
}

/// Live cloud cleanup via Groq. Gated on GROQ_API_KEY being present in the
/// environment (skips in CI / for contributors without a key). Exercises the
/// real cloud path: GroqCleanupEngine -> OpenAICompatibleClient -> CleanupPipeline,
/// including the app-aware formatting hint.
final class LiveGroqCleanupTests: XCTestCase {
    func testGroqCloudCleanupThroughPipeline() async throws {
        let key = ProcessInfo.processInfo.environment["GROQ_API_KEY"] ?? ""
        try XCTSkipUnless(!key.isEmpty, "Set GROQ_API_KEY to run the live Groq test")

        let engine = GroqCleanupEngine(apiKey: key, timeout: 8)
        let pipeline = CleanupPipeline(engines: [engine])

        let raw = "um so basically lets uh meet at three tomorrow to talk about the you know the project"
        let cleaned = await pipeline.cleanup(CleanupRequest(raw: raw))
        print("GROQ cleanup: \(cleaned)")
        XCTAssertFalse(cleaned.isEmpty)
        XCTAssertFalse(cleaned.lowercased().contains(" um "))
        XCTAssertFalse(cleaned.lowercased().contains(" uh "))
        // New behavior: spoken number "three" is written as the digit "3".
        XCTAssertTrue(cleaned.contains("3"), "expected 'three' digitized to '3', got: \(cleaned)")
        XCTAssertFalse(cleaned.lowercased().contains("three"), "number should be digitized, got: \(cleaned)")
        XCTAssertTrue(cleaned.lowercased().contains("project"))

        // App-aware formatting: an email hint should produce more formal prose
        // than a terse-messaging hint for the same utterance.
        let emailHint = AppProfileDefaults.hint(forBundleID: "com.apple.mail")
        let email = await pipeline.cleanup(CleanupRequest(raw: raw, appHint: emailHint))
        print("GROQ email-formatted: \(email)")
        XCTAssertFalse(email.isEmpty)
    }
}
