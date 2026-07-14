import XCTest
@testable import LearningKit

final class TokenDiffTests: XCTestCase {
    func testSingleWordSubstitution() {
        let subs = TokenDiff.substitutions(from: "call vidon tomorrow", to: "call Vidhaan tomorrow")
        XCTAssertEqual(subs, [Substitution(from: "vidon", to: "Vidhaan")])
    }

    func testNoChange() {
        XCTAssertEqual(TokenDiff.substitutions(from: "hello world", to: "hello world"), [])
    }

    func testCaseOnlyChangeIgnored() {
        // Same word, different case is not a vocabulary substitution.
        XCTAssertEqual(TokenDiff.substitutions(from: "hello world", to: "Hello world"), [])
    }

    func testTwoSubstitutions() {
        let subs = TokenDiff.substitutions(from: "meet kube and vidon", to: "meet Kubernetes and Vidhaan")
        XCTAssertTrue(subs.contains(Substitution(from: "kube", to: "Kubernetes")))
        XCTAssertTrue(subs.contains(Substitution(from: "vidon", to: "Vidhaan")))
    }

    func testInsertionIsNotSubstitution() {
        // Pure insertion (no word removed) shouldn't produce a substitution.
        let subs = TokenDiff.substitutions(from: "meet at three", to: "let's meet at three")
        XCTAssertEqual(subs, [])
    }
}

final class CorrectionObserverTests: XCTestCase {
    func testSuggestsAfterThreshold() {
        let observer = CorrectionObserver(store: InMemoryCorrectionCountStore(), threshold: 2)
        // First correction: recorded but below threshold.
        XCTAssertEqual(observer.record(injected: "call vidon", corrected: "call Vidhaan"), [])
        // Second: crosses threshold → suggested.
        let suggestions = observer.record(injected: "email vidon", corrected: "email Vidhaan")
        XCTAssertEqual(suggestions, [Substitution(from: "vidon", to: "Vidhaan")])
    }

    func testDoesNotResuggestAfterThreshold() {
        let observer = CorrectionObserver(store: InMemoryCorrectionCountStore(), threshold: 2)
        _ = observer.record(injected: "a vidon", corrected: "a Vidhaan")
        _ = observer.record(injected: "b vidon", corrected: "b Vidhaan")   // suggested here
        // Third time should not re-suggest (count already past threshold).
        XCTAssertEqual(observer.record(injected: "c vidon", corrected: "c Vidhaan"), [])
    }

    func testIgnoresLargeRewrites() {
        let observer = CorrectionObserver(store: InMemoryCorrectionCountStore(), threshold: 1, maxSubstitutionsPerCorrection: 2)
        // Many substitutions = a rewrite, not a vocab fix.
        let subs = observer.record(
            injected: "the cat sat on the mat",
            corrected: "a dog ran through some grass"
        )
        XCTAssertEqual(subs, [])
    }

    func testClearStopsSuggestion() {
        let store = InMemoryCorrectionCountStore()
        let observer = CorrectionObserver(store: store, threshold: 2)
        _ = observer.record(injected: "x vidon", corrected: "x Vidhaan")
        observer.clear(Substitution(from: "vidon", to: "Vidhaan"))
        // After clearing, it takes threshold hits again.
        XCTAssertEqual(observer.record(injected: "y vidon", corrected: "y Vidhaan"), [])
    }

    func testUserDefaultsStorePersists() {
        let suite = UserDefaults(suiteName: "com.flowclone.test.\(UUID().uuidString)")!
        let store = UserDefaultsCorrectionCountStore(defaults: suite)
        let sub = Substitution(from: "kube", to: "Kubernetes")
        XCTAssertEqual(store.increment(sub), 1)
        XCTAssertEqual(store.increment(sub), 2)
        XCTAssertEqual(store.count(for: sub), 2)
        // A fresh store over the same defaults sees the persisted value.
        let store2 = UserDefaultsCorrectionCountStore(defaults: suite)
        XCTAssertEqual(store2.count(for: sub), 2)
    }
}
