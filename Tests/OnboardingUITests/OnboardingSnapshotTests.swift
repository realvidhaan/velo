import XCTest
@testable import OnboardingUI

@MainActor
final class OnboardingSnapshotTests: XCTestCase {
    func testRenderOnboarding() {
        let dir: URL
        if let override = ProcessInfo.processInfo.environment["VELO_SNAPSHOT_DIR"] {
            dir = URL(fileURLWithPath: override)
        } else {
            dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fc-onboarding")
        }
        let urls = OnboardingSnapshot.render(to: dir)
        XCTAssertEqual(urls.count, 3)
        print("onboarding snapshots written to \(dir.path)")
    }

    func testStateCompletion() {
        XCTAssertFalse(OnboardingState().isComplete)
        XCTAssertTrue(OnboardingState(microphoneGranted: true, inputMonitoringGranted: true,
                                      accessibilityGranted: true).isComplete)
    }
}
