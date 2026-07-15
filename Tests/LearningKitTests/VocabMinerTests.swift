import XCTest
@testable import LearningKit

final class VocabMinerTests: XCTestCase {
    func testSuggestsFrequentProperNoun() {
        let transcripts = [
            "let's ship FlowClone today",
            "FlowClone is looking good",
            "I love using FlowClone",
        ]
        let candidates = VocabMiner.candidates(from: transcripts, existing: [], minCount: 3)
        XCTAssertEqual(candidates.first?.term, "FlowClone")
        XCTAssertEqual(candidates.first?.count, 3)
    }

    func testFiltersCommonWords() {
        // "really" appears often but is a common word — never suggested.
        let transcripts = Array(repeating: "this is really really good", count: 5)
        let candidates = VocabMiner.candidates(from: transcripts, existing: [], minCount: 3)
        XCTAssertFalse(candidates.contains { $0.term.lowercased() == "really" })
        XCTAssertFalse(candidates.contains { $0.term.lowercased() == "good" })
    }

    func testExcludesExistingTerms() {
        let transcripts = Array(repeating: "WhisperKit runs on device", count: 4)
        let candidates = VocabMiner.candidates(from: transcripts, existing: ["whisperkit"], minCount: 3)
        XCTAssertFalse(candidates.contains { $0.term == "WhisperKit" })
    }

    func testRespectsMinCount() {
        let transcripts = ["Vidhaan shipped it", "Vidhaan again"]
        XCTAssertTrue(VocabMiner.candidates(from: transcripts, existing: [], minCount: 3).isEmpty)
        XCTAssertFalse(VocabMiner.candidates(from: transcripts, existing: [], minCount: 2).isEmpty)
    }

    func testKeepsIdentifiersAndProductNames() {
        let transcripts = Array(repeating: "call useState then push to GitHub", count: 3)
        let terms = Set(VocabMiner.candidates(from: transcripts, existing: [], minCount: 3).map(\.term))
        XCTAssertTrue(terms.contains("useState"))
        XCTAssertTrue(terms.contains("GitHub"))
    }

    func testPrefersCapitalizedDisplayForm() {
        // Mixed casing across mentions → the distinctive (capitalized) form wins.
        let transcripts = ["i met vidhaan", "Vidhaan called", "saw Vidhaan again"]
        let candidates = VocabMiner.candidates(from: transcripts, existing: [], minCount: 3)
        XCTAssertEqual(candidates.first?.term, "Vidhaan")
        XCTAssertEqual(candidates.first?.count, 3)
    }
}
