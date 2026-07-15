import XCTest
import AVFoundation
@testable import AudioService

/// Regression test for the Fn-press crash: the tap block runs on AVAudioEngine's
/// realtime thread and used to call main-actor-isolated static helpers
/// (`rms`, `copy`), which tripped the Swift 6 executor check and SIGTRAP'd the
/// instant the first buffer arrived. This drives the real engine so the tap
/// actually fires off-main; before the fix the process would crash here.
///
/// Gated behind FLOWCLONE_RUN_AUDIO_TEST=1 because it needs a real audio input
/// device + microphone permission (absent on CI runners).
final class AudioCaptureServiceTests: XCTestCase {
    @MainActor
    func testRealtimeTapDoesNotTrap() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FLOWCLONE_RUN_AUDIO_TEST"] == "1",
            "Set FLOWCLONE_RUN_AUDIO_TEST=1 (needs mic access) to run the live audio-tap test"
        )
        guard AudioCaptureService.microphoneAuthorized else {
            throw XCTSkip("Microphone not authorized for the test host")
        }

        let service = AudioCaptureService()
        let tapFired = expectation(description: "tap delivered at least one buffer")
        tapFired.assertForOverFulfill = false
        service.onLevel = { _ in tapFired.fulfill() }

        try service.start()
        defer { service.stop() }

        // If the isolation bug were present, the process would SIGTRAP on the
        // realtime thread before this wait returns. Reaching the assertion at all
        // means the tap ran off-main without trapping.
        await fulfillment(of: [tapFired], timeout: 3.0)
        XCTAssertGreaterThanOrEqual(service.level, 0)
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
