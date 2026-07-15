import XCTest
@testable import SettingsUI

@MainActor
final class SettingsSnapshotTests: XCTestCase {
    func testRenderSettingsViews() throws {
        let dir: URL
        if let override = ProcessInfo.processInfo.environment["FLOWCLONE_SNAPSHOT_DIR"] {
            dir = URL(fileURLWithPath: override)
        } else {
            dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fc-settings-snaps")
        }
        let urls = try SettingsSnapshot.render(to: dir)
        XCTAssertEqual(urls.count, 4)
        for url in urls {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            XCTAssertGreaterThan(size ?? 0, 500)
        }
        print("settings snapshots written to \(dir.path)")
    }
}
