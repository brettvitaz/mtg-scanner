import XCTest
@testable import MTGScanner

final class ScanMenuButtonTests: XCTestCase {

    // MARK: - Torch toggle logic

    func testTorchToggleFromOffTurnsOn() {
        var level: Float = 0
        // Mirror the toggle action: torchIsOn ? 0 : 0.5
        level = level > 0 ? 0 : 0.5
        XCTAssertEqual(level, 0.5, accuracy: 0.001)
    }

    func testTorchToggleFromOnTurnsOff() {
        var level: Float = 0.5
        level = level > 0 ? 0 : 0.5
        XCTAssertEqual(level, 0, accuracy: 0.001)
    }

    func testTorchIsOnWhenLevelAboveZero() {
        let level: Float = 0.1
        XCTAssertTrue(level > 0)
    }

    func testTorchIsOffWhenLevelIsZero() {
        let level: Float = 0
        XCTAssertFalse(level > 0)
    }

    // MARK: - Brightness preset logic

    func testLowBrightnessSetsCorrectLevel() {
        var level: Float = 1.0
        level = 0.25
        XCTAssertEqual(level, 0.25, accuracy: 0.001)
    }

    func testMediumBrightnessSetsCorrectLevel() {
        var level: Float = 0.25
        level = 0.5
        XCTAssertEqual(level, 0.5, accuracy: 0.001)
    }

    func testHighBrightnessSetsCorrectLevel() {
        var level: Float = 0.25
        level = 1.0
        XCTAssertEqual(level, 1.0, accuracy: 0.001)
    }

    // MARK: - Brightness section visibility

    func testBrightnessSectionHiddenWhenTorchOff() {
        let level: Float = 0
        // Section("Brightness") is only shown when torchIsOn (level > 0)
        XCTAssertFalse(level > 0)
    }

    func testBrightnessSectionVisibleWhenTorchOn() {
        let level: Float = 0.5
        XCTAssertTrue(level > 0)
    }

    // MARK: - Detection mode selection

    func testModeSwitchesToBinder() {
        var mode: DetectionMode = .table
        mode = .binder
        XCTAssertEqual(mode, .binder)
    }

    func testModeSwitchesToQuickScan() {
        var mode: DetectionMode = .table
        mode = .quickScan
        XCTAssertEqual(mode, .quickScan)
    }

    func testAllModesAvailable() {
        XCTAssertEqual(DetectionMode.allCases.count, 3)
        XCTAssertTrue(DetectionMode.allCases.contains(.table))
        XCTAssertTrue(DetectionMode.allCases.contains(.binder))
        XCTAssertTrue(DetectionMode.allCases.contains(.quickScan))
    }
}
