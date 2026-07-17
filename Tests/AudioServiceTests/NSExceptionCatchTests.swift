import XCTest
import AVFoundation
import ObjCSupport
@testable import AudioService

/// Regression test for the menu-bar-death crash: `-[AVAudioNode installTapOnBus:]`
/// reports failure by *raising* an Obj-C `NSException`, which a Swift `do/catch`
/// cannot catch — so the runtime `abort()`s and Velo vanishes from the menu bar.
/// `AudioCaptureService` now wraps those calls in `VeloRunCatchingNSException`.
/// These tests prove the shim actually converts a raise into a Swift-visible
/// `NSError` (and passes success through), so the wrapping can't silently regress.
final class NSExceptionCatchTests: XCTestCase {
    func testCatchesRaisedNSException() {
        let error = VeloRunCatchingNSException {
            NSException(name: .genericException, reason: "boom", userInfo: nil).raise()
        }
        XCTAssertNotNil(error, "a raised NSException must be returned as an NSError, not abort the process")
        XCTAssertEqual(error?.localizedDescription, "boom")
    }

    func testPassesThroughOnSuccess() {
        var ran = false
        let error = VeloRunCatchingNSException { ran = true }
        XCTAssertNil(error, "a normally-returning block must yield nil")
        XCTAssertTrue(ran)
    }

    /// The real thing: reproduce an actual `-[AVAudioNode installTapOnBus:]` raise
    /// — the exact API and failure *class* behind the user's crash — by installing
    /// a tap whose sample rate disagrees with the input node's hardware format.
    /// Bare, this aborts the process (SIGABRT, "required condition is false…"),
    /// which is precisely how Velo vanished from the menu bar. Through the shim it
    /// must come back as a Swift-visible `NSError`. Gated on a real mic like the
    /// other live-audio tests.
    @MainActor
    func testRealInstallTapRaiseIsCaught() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["VELO_RUN_AUDIO_TEST"] == "1",
            "Set VELO_RUN_AUDIO_TEST=1 (needs mic access) to run the live installTap-raise test"
        )
        guard AudioCaptureService.microphoneAuthorized else {
            throw XCTSkip("Microphone not authorized for the test host")
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        engine.prepare()
        let hw = input.outputFormat(forBus: 0)
        try XCTSkipUnless(hw.sampleRate > 0 && hw.channelCount > 0, "no live input format")

        // A valid but deliberately mismatched sample rate → installTapOnBus raises.
        let mismatched = hw.sampleRate == 44_100 ? 48_000.0 : 44_100.0
        let badFormat = AVAudioFormat(standardFormatWithSampleRate: mismatched,
                                      channels: hw.channelCount)!

        let error = VeloRunCatchingNSException {
            input.installTap(onBus: 0, bufferSize: 4096, format: badFormat) { _, _ in }
        }
        input.removeTap(onBus: 0)

        XCTAssertNotNil(error,
            "a real installTapOnBus format-mismatch raise must be caught as an NSError, not abort the app")
    }
}
