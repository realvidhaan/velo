import XCTest
import AVFoundation
@testable import AudioService

/// Regression test for the Fn-press crash: the tap block runs on AVAudioEngine's
/// realtime thread and used to call main-actor-isolated static helpers
/// (`rms`, `copy`), which tripped the Swift 6 executor check and SIGTRAP'd the
/// instant the first buffer arrived. This drives the real engine so the tap
/// actually fires off-main; before the fix the process would crash here.
///
/// Gated behind VELO_RUN_AUDIO_TEST=1 because it needs a real audio input
/// device + microphone permission (absent on CI runners).
final class AudioCaptureServiceTests: XCTestCase {
    @MainActor
    func testRealtimeTapDoesNotTrap() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["VELO_RUN_AUDIO_TEST"] == "1",
            "Set VELO_RUN_AUDIO_TEST=1 (needs mic access) to run the live audio-tap test"
        )
        guard AudioCaptureService.microphoneAuthorized else {
            throw XCTSkip("Microphone not authorized for the test host")
        }

        let service = AudioCaptureService()
        let tapFired = expectation(description: "tap delivered at least one buffer")
        tapFired.assertForOverFulfill = false
        service.onLevel = { _ in tapFired.fulfill() }

        try await service.start()
        defer { service.stop() }

        // If the isolation bug were present, the process would SIGTRAP on the
        // realtime thread before this wait returns. Reaching the assertion at all
        // means the tap ran off-main without trapping.
        await fulfillment(of: [tapFired], timeout: 3.0)
        XCTAssertGreaterThanOrEqual(service.level, 0)
    }

    /// Regression test for the "quits on the 2nd Fn press" crash: after one
    /// start/stop cycle, a second `start()` re-read a stale input format (0 Hz /
    /// 0 ch) and `installTapOnBus` raised an Obj-C NSException → abort(). The fix
    /// prepares before reading the format, defensively removes any prior tap, and
    /// validates the format. Driving start → stop → start must not crash and must
    /// deliver buffers on the second run.
    @MainActor
    func testRestartDoesNotCrash() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["VELO_RUN_AUDIO_TEST"] == "1",
            "Set VELO_RUN_AUDIO_TEST=1 (needs mic access) to run the restart test"
        )
        guard AudioCaptureService.microphoneAuthorized else {
            throw XCTSkip("Microphone not authorized for the test host")
        }

        let service = AudioCaptureService()

        // First cycle.
        try await service.start()
        service.stop()

        // Second cycle — this is where the crash used to happen.
        let tapFired = expectation(description: "second start delivered a buffer")
        tapFired.assertForOverFulfill = false
        service.onLevel = { _ in tapFired.fulfill() }
        try await service.start()
        defer { service.stop() }

        await fulfillment(of: [tapFired], timeout: 3.0)
    }

    /// Regression test for the "wait a while, press Fn → 'Couldn't start
    /// microphone', can't dictate" bug: after idle the input hardware powers down
    /// and reports a 0 Hz format for a beat, and the old *synchronous* retry
    /// re-read that same 0 Hz instantly and failed. `retryingColdStart` must keep
    /// retrying with a settle delay until an attempt succeeds. No audio hardware
    /// needed — we drive the loop with a closure that fails the first two attempts
    /// (as a cold 0 Hz read would) then succeeds.
    @MainActor
    func testColdStartRetriesUntilItSucceeds() async throws {
        var attempts = 0
        try await AudioCaptureService.retryingColdStart(
            budget: .milliseconds(1000), delay: .milliseconds(10)
        ) { n in
            attempts = n
            if n < 3 { throw AudioCaptureError.invalidInputFormat }  // hardware still waking
        }
        XCTAssertEqual(attempts, 3, "should retry past the transient 0 Hz reads and then succeed")
    }

    /// The retry is bounded: if the format never recovers, `start()` must give up
    /// within the budget and rethrow rather than spin forever — so the pill shows
    /// an actionable error instead of hanging.
    @MainActor
    func testColdStartGivesUpAfterBudget() async {
        var attempts = 0
        // Non-divisible budget/delay so a full final `delay` would overshoot the
        // budget unless the sleep is clamped to the remaining time.
        let budget: Duration = .milliseconds(100)
        let started = ContinuousClock.now
        do {
            try await AudioCaptureService.retryingColdStart(
                budget: budget, delay: .milliseconds(35)
            ) { n in
                attempts = n
                throw AudioCaptureError.invalidInputFormat  // never recovers
            }
            XCTFail("should have thrown after exhausting the budget")
        } catch let error as AudioCaptureError {
            guard case .invalidInputFormat = error else {
                return XCTFail("should rethrow the last attempt's error, got \(error)")
            }
            XCTAssertGreaterThanOrEqual(attempts, 2, "should retry at least once before giving up")
            // Clamped sleeps must keep total time within budget (+ generous
            // scheduler tolerance) rather than overshooting by a full delay.
            let elapsed = ContinuousClock.now - started
            XCTAssertLessThan(elapsed, budget + .milliseconds(150),
                              "give-up should respect the budget, took \(elapsed)")
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    /// Regression test for the sleep/wake crash: AVFAudio posts
    /// `.AVAudioEngineConfigurationChange` on a background queue when the audio
    /// unit is rebuilt on wake. The handler used to be `@MainActor`-isolated, so
    /// being invoked off-main tripped Swift 6's executor check and SIGTRAP'd the
    /// whole app every time the Mac woke. It's now `nonisolated`; invoking it off
    /// the main thread must return cleanly. No audio hardware needed.
    @MainActor
    func testConfigurationChangeOffMainDoesNotTrap() async {
        let service = AudioCaptureService()
        let handled = expectation(description: "config-change handled off-main without trapping")
        DispatchQueue.global(qos: .userInitiated).async {
            service.configurationChanged(Notification(name: .AVAudioEngineConfigurationChange))
            handled.fulfill()
        }
        await fulfillment(of: [handled], timeout: 2.0)
    }
}
