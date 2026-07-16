import XCTest
@testable import TranscriptionKit

final class BiasPromptTests: XCTestCase {
    func testNilWhenNoTerms() {
        XCTAssertNil(BiasPrompt.build(terms: []))
        XCTAssertNil(BiasPrompt.build(terms: ["   ", ""]))
    }

    func testRendersExampleStylePhrase() {
        let prompt = BiasPrompt.build(terms: ["Velo"])
        XCTAssertEqual(prompt, "Vocabulary: Velo.")
    }

    func testHighestPriorityTermIsLast() {
        // Terms are passed most-important first; the most-important should land at
        // the END of the phrase (where the decoder weights it most).
        let prompt = BiasPrompt.build(terms: ["Alpha", "Beta", "Gamma"])
        XCTAssertEqual(prompt, "Vocabulary: Gamma, Beta, Alpha.")
    }

    func testRespectsTokenBudget() {
        // A large list must be truncated to stay under the ~224-token cap.
        let many = (0..<500).map { "term\($0)verylongword" }
        let prompt = BiasPrompt.build(terms: many)!
        XCTAssertLessThanOrEqual(BiasPrompt.estimateTokens(prompt), BiasPrompt.maxTokens + 2)
        // The first-passed (highest-priority) terms survive; later ones are dropped.
        XCTAssertTrue(prompt.contains("term0verylongword"))
    }

    func testTrimsWhitespaceTerms() {
        let prompt = BiasPrompt.build(terms: ["  Swift  ", "SwiftData"])
        XCTAssertEqual(prompt, "Vocabulary: SwiftData, Swift.")
    }
}
