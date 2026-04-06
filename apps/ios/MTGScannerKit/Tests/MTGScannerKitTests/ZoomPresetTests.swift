import XCTest
@testable import MTGScannerKit

final class ZoomPresetTests: XCTestCase {

    // MARK: - isActive

    func testIsActiveAtExactPreset() {
        XCTAssertTrue(ZoomPresetControl.isActive(1.0, currentZoom: 1.0))
        XCTAssertTrue(ZoomPresetControl.isActive(2.0, currentZoom: 2.0))
        XCTAssertTrue(ZoomPresetControl.isActive(5.0, currentZoom: 5.0))
    }

    func testIsActiveWithinTolerance() {
        XCTAssertTrue(ZoomPresetControl.isActive(2.0, currentZoom: 2.11))
        XCTAssertTrue(ZoomPresetControl.isActive(2.0, currentZoom: 1.89))
    }

    func testIsActiveOutsideTolerance() {
        XCTAssertFalse(ZoomPresetControl.isActive(2.0, currentZoom: 2.13))
        XCTAssertFalse(ZoomPresetControl.isActive(1.0, currentZoom: 1.13))
    }

    func testNoPresetActiveWhenBetweenPresets() {
        let zoom: CGFloat = 1.5
        let anyActive = ZoomPresetControl.presets.contains { preset in
            ZoomPresetControl.isActive(preset, currentZoom: zoom)
        }
        XCTAssertFalse(anyActive)
    }

    func testOnlyOnePresetActiveAtATime() {
        for preset in ZoomPresetControl.presets {
            let activeCount = ZoomPresetControl.presets.filter { p in
                ZoomPresetControl.isActive(p, currentZoom: preset)
            }.count
            XCTAssertEqual(activeCount, 1)
        }
    }

    // MARK: - presets

    func testPresetsContainExpectedValues() {
        XCTAssertEqual(ZoomPresetControl.presets, [1, 2, 3, 5])
    }
}
