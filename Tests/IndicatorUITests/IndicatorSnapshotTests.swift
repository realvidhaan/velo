import XCTest
import SwiftUI
@testable import IndicatorUI

@MainActor
final class IndicatorSnapshotTests: XCTestCase {
    /// Renders the indicator states to PNGs. Writes to $VELO_SNAPSHOT_DIR
    /// if set (so a human/agent can inspect them), else a temp dir. Asserts the
    /// renderer produced non-trivial images.
    func testRenderIndicatorSnapshots() {
        let dir: URL
        if let override = ProcessInfo.processInfo.environment["VELO_SNAPSHOT_DIR"] {
            dir = URL(fileURLWithPath: override)
        } else {
            dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fc-snaps")
        }

        let urls = IndicatorSnapshot.render(to: dir)
        XCTAssertEqual(urls.count, IndicatorSnapshot.allCases.count, "all cases should render")

        for url in urls {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            XCTAssertGreaterThan(size ?? 0, 500, "PNG at \(url.lastPathComponent) should be non-trivial")
        }
        print("snapshots written to \(dir.path)")
    }
}
