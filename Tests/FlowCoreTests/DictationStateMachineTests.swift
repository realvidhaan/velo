import XCTest
@testable import FlowCore

final class DictationStateMachineTests: XCTestCase {
    private func reduce(_ s: DictationState, _ e: DictationEvent) -> DictationState {
        DictationStateMachine.reduce(s, e)
    }

    func testHappyPath() {
        var s: DictationState = .idle
        s = reduce(s, .hotkeyDown(.dictation)); XCTAssertEqual(s, .recording(.dictation))
        s = reduce(s, .hotkeyUp); XCTAssertEqual(s, .transcribing(.dictation))
        s = reduce(s, .transcriptFinalized("hello world")); XCTAssertEqual(s, .cleaning(.dictation, raw: "hello world"))
        s = reduce(s, .cleaned("Hello world.")); XCTAssertEqual(s, .injecting(.dictation, text: "Hello world."))
        s = reduce(s, .injected); XCTAssertEqual(s, .idle)
    }

    func testEmptyTranscriptReturnsToIdle() {
        let s = reduce(.transcribing(.dictation), .transcriptFinalized("   "))
        XCTAssertEqual(s, .idle)
    }

    func testCancelFromEveryBusyStateReturnsIdle() {
        let busy: [DictationState] = [
            .recording(.dictation),
            .transcribing(.dictation),
            .cleaning(.dictation, raw: "x"),
            .injecting(.dictation, text: "x"),
        ]
        for state in busy {
            XCTAssertEqual(reduce(state, .cancel), .idle, "cancel should reset \(state)")
        }
    }

    func testFailureFromBusySurfacesError() {
        let s = reduce(.cleaning(.dictation, raw: "x"), .failed("boom"))
        XCTAssertEqual(s, .error("boom"))
        XCTAssertEqual(reduce(s, .reset), .idle)
    }

    func testOverlappingHotkeyDownWhileBusyIsIgnored() {
        let s = reduce(.transcribing(.dictation), .hotkeyDown(.dictation))
        XCTAssertEqual(s, .transcribing(.dictation))
    }

    func testHotkeyUpWhenIdleIsNoOp() {
        XCTAssertEqual(reduce(.idle, .hotkeyUp), .idle)
    }

    func testCancelWhenIdleIsNoOp() {
        XCTAssertEqual(reduce(.idle, .cancel), .idle)
    }

    /// No dead ends: from every state there exists an event returning to idle.
    func testNoDeadEnds() {
        let states: [DictationState] = [
            .idle, .recording(.dictation), .transcribing(.dictation),
            .cleaning(.dictation, raw: "x"), .injecting(.dictation, text: "x"),
            .error("e"),
        ]
        let events: [DictationEvent] = [
            .hotkeyDown(.dictation), .hotkeyUp, .transcriptFinalized(""),
            .transcriptFinalized("x"), .cleaned("x"), .injected, .cancel,
            .failed("e"), .reset,
        ]
        for state in states {
            let reachesIdle = events.contains { reduce(state, $0) == .idle }
            XCTAssertTrue(reachesIdle, "no path to idle from \(state)")
        }
    }
}
