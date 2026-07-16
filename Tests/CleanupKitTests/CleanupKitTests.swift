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
        let s = CleanupPrompt.system(dictionary: ["Vidhaan", "Velo"], appHint: nil)
        XCTAssertTrue(s.contains("Vidhaan"))
        XCTAssertTrue(s.contains("Velo"))
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

    func testSystemIncludesStructuredFormattingRules() {
        let s = CleanupPrompt.system(dictionary: [], appHint: nil).lowercased()
        XCTAssertTrue(s.contains("numbered list"))
        XCTAssertTrue(s.contains("bulleted list"))
        XCTAssertTrue(s.contains("comma-separated list"))
        XCTAssertTrue(s.contains("paragraph"))
        // Guardrail: never fabricate list items.
        XCTAssertTrue(s.contains("never invent"))
    }

    func testEmailPersonalityAddsEmailStructure() {
        let style = CleanupStyle(tone: .formal, structure: .email, keepTrailingPunctuation: true, hint: "email prose")
        let s = CleanupPrompt.system(dictionary: [], appHint: nil, style: style).lowercased()
        XCTAssertTrue(s.contains("email"))
        XCTAssertTrue(s.contains("greeting"))
        XCTAssertTrue(s.contains("sign-off"))
    }

    func testCasualPersonalityDropsTrailingPeriod() {
        let style = CleanupStyle(tone: .casual, structure: .prose, keepTrailingPunctuation: false, hint: "")
        let s = CleanupPrompt.system(dictionary: [], appHint: nil, style: style).lowercased()
        XCTAssertTrue(s.contains("do not end the message with a period"))
    }

    func testVerbatimPersonalityOverridesFormatting() {
        let style = CleanupStyle(tone: .verbatim, structure: .code, keepTrailingPunctuation: false, hint: "")
        let s = CleanupPrompt.system(dictionary: [], appHint: nil, style: style).lowercased()
        XCTAssertTrue(s.contains("verbatim"))
        XCTAssertTrue(s.contains("ignore the formatting rules"))
    }

    func testDefaultExamplesDemonstrateStructure() {
        let examples = CleanupPrompt.defaultExamples
        XCTAssertFalse(examples.isEmpty)
        // One teaches numbered lists, one teaches comma lists.
        XCTAssertTrue(examples.contains { $0.output.contains("1.") && $0.output.contains("2.") })
        XCTAssertTrue(examples.contains { $0.output.contains(", ") && $0.output.contains(", and ") })
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

    func testBuiltInPersonalities() {
        let mail = AppProfileDefaults.personality(forBundleID: "com.apple.mail")
        XCTAssertEqual(mail?.style.structure, .email)
        XCTAssertEqual(mail?.style.tone, .formal)
        XCTAssertFalse(mail?.examples.isEmpty ?? true, "Mail ships an email few-shot example")

        let messages = AppProfileDefaults.personality(forBundleID: "com.apple.MobileSMS")
        XCTAssertEqual(messages?.style.tone, .casual)
        XCTAssertEqual(messages?.style.keepTrailingPunctuation, false)

        let vscode = AppProfileDefaults.personality(forBundleID: "com.microsoft.VSCode")
        XCTAssertEqual(vscode?.style.tone, .verbatim)
        XCTAssertEqual(vscode?.style.structure, .code)

        XCTAssertNil(AppProfileDefaults.personality(forBundleID: "com.example.unknown"))
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
            ProcessInfo.processInfo.environment["VELO_RUN_LLM_TEST"] == "1",
            "Set VELO_RUN_LLM_TEST=1 to run the live Apple Foundation Models test"
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

    /// Structured formatting: enumerations become numbered lists, inline items
    /// become comma lists, and the email personality produces email shape.
    func testGroqStructuredFormatting() async throws {
        let key = ProcessInfo.processInfo.environment["GROQ_API_KEY"] ?? ""
        try XCTSkipUnless(!key.isEmpty, "Set GROQ_API_KEY to run the live Groq test")

        let engine = GroqCleanupEngine(apiKey: key, timeout: 10)
        let pipeline = CleanupPipeline(engines: [engine])
        let examples = CleanupPrompt.defaultExamples

        // (a) Enumeration → numbered list.
        let listRaw = "okay so first we need to buy milk second call mom and then third finish the report"
        let list = await pipeline.cleanup(CleanupRequest(raw: listRaw, examples: examples))
        print("GROQ list: \(list)")
        XCTAssertTrue(list.contains("1.") && list.contains("2.") && list.contains("3."),
                      "expected a numbered list, got: \(list)")

        // (b) Inline items → comma list with Oxford comma.
        let commaRaw = "we need to grab eggs milk bread and butter"
        let comma = await pipeline.cleanup(CleanupRequest(raw: commaRaw, examples: examples))
        print("GROQ comma list: \(comma)")
        XCTAssertTrue(comma.contains("eggs, milk, bread"), "expected a comma list, got: \(comma)")

        // (c) Email personality → greeting/body structure (multi-line).
        let mail = AppProfileDefaults.personality(forBundleID: "com.apple.mail")
        let emailRaw = "hey sarah just following up on the proposal can we meet thursday thanks alex"
        let email = await pipeline.cleanup(CleanupRequest(
            raw: emailRaw, style: mail?.style, examples: examples + (mail?.examples ?? [])
        ))
        print("GROQ email: \(email)")
        XCTAssertFalse(email.isEmpty)
        XCTAssertTrue(email.contains("\n"), "expected multi-line email structure, got: \(email)")
    }
}
