import XCTest
import AVFoundation
@testable import TranscriptionKit

/// Unit tests for the `.auto` fallback chain — no network. Stub engines let us
/// prove the fall-through order and that a working engine's result is returned.
final class AutoTranscriptionEngineTests: XCTestCase {
    func testFallsThroughToNextEngineOnError() async throws {
        let failing = StubEngine(name: "failing", behavior: .throwError)
        let working = StubEngine(name: "working", behavior: .returnText("hello world"))
        let auto = AutoTranscriptionEngine(engines: [failing, working])

        let session = try await auto.makeSession(contextualStrings: [])
        let text = try await session.finish()

        XCTAssertEqual(text, "hello world")
        XCTAssertTrue(failing.makeSessionCalled)
        XCTAssertTrue(working.makeSessionCalled)
    }

    func testReturnsFirstEngineResultWithoutTryingRest() async throws {
        let first = StubEngine(name: "first", behavior: .returnText("first result"))
        let second = StubEngine(name: "second", behavior: .returnText("second result"))
        let auto = AutoTranscriptionEngine(engines: [first, second])

        let text = try await auto.makeSession(contextualStrings: []).finish()

        XCTAssertEqual(text, "first result")
        XCTAssertFalse(second.makeSessionCalled, "second engine should not be reached")
    }

    func testBlankResultIsReturnedNotTreatedAsFailure() async throws {
        // Silence → empty transcript is a valid answer; don't fall through.
        let silent = StubEngine(name: "silent", behavior: .returnText(""))
        let backup = StubEngine(name: "backup", behavior: .returnText("should not run"))
        let auto = AutoTranscriptionEngine(engines: [silent, backup])

        let text = try await auto.makeSession(contextualStrings: []).finish()

        XCTAssertEqual(text, "")
        XCTAssertFalse(backup.makeSessionCalled)
    }

    func testThrowsWhenAllEnginesFail() async throws {
        let a = StubEngine(name: "a", behavior: .throwError)
        let b = StubEngine(name: "b", behavior: .throwError)
        let auto = AutoTranscriptionEngine(engines: [a, b])

        do {
            _ = try await auto.makeSession(contextualStrings: []).finish()
            XCTFail("expected an error when every engine fails")
        } catch {
            // expected
        }
    }

    func testMakeSessionFailureAlsoFallsThrough() async throws {
        let unavailable = StubEngine(name: "unavailable", behavior: .failMakeSession)
        let working = StubEngine(name: "working", behavior: .returnText("ok"))
        let auto = AutoTranscriptionEngine(engines: [unavailable, working])

        let text = try await auto.makeSession(contextualStrings: []).finish()
        XCTAssertEqual(text, "ok")
    }
}

/// Configurable fake engine for exercising the fallback chain.
private final class StubEngine: TranscriptionEngine, @unchecked Sendable {
    enum Behavior {
        case returnText(String)
        case throwError
        case failMakeSession
    }

    let displayName: String
    private let behavior: Behavior
    private(set) var makeSessionCalled = false

    init(name: String, behavior: Behavior) {
        self.displayName = name
        self.behavior = behavior
    }

    func prepare() async throws {}

    func makeSession(contextualStrings: [String]) async throws -> any TranscriptionSession {
        makeSessionCalled = true
        if case .failMakeSession = behavior {
            throw TranscriptionError.engineUnavailable(displayName)
        }
        return StubSession(behavior: behavior)
    }
}

private final class StubSession: TranscriptionSession, @unchecked Sendable {
    private let behavior: StubEngine.Behavior
    init(behavior: StubEngine.Behavior) { self.behavior = behavior }

    func feed(_ buffer: AVAudioPCMBuffer) {}

    func finish() async throws -> String {
        switch behavior {
        case .returnText(let text): return text
        case .throwError: throw TranscriptionError.engineUnavailable("finish failed")
        case .failMakeSession: return ""
        }
    }

    func cancel() async {}
}

final class WhisperKitInstalledCheckTests: XCTestCase {
    /// The check must not crash and must return a Bool for the default model.
    /// (In CI the model is absent → false; this guards the path logic.)
    func testIsModelInstalledDoesNotCrash() {
        _ = WhisperKitEngine.isModelInstalled()
        _ = WhisperKitEngine.isModelInstalled(model: "nonexistent-model")
        XCTAssertFalse(WhisperKitEngine.isModelInstalled(model: "definitely-not-a-real-model"))
    }
}
