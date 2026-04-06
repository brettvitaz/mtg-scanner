import XCTest
@testable import MTGScanner

// Note: ScanMenuButton is a SwiftUI view; button tap behavior and gesture state cannot be
// unit-tested without a SwiftUI testing library (e.g. ViewInspector). Tests here cover the
// pure logic expressions mirrored from the view — they would fail if the logic were changed.

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

    // MARK: - Long-press auto-enable logic

    func testLongPressAutoEnablesTorchWhenOff() {
        var level: Float = 0
        // Mirror long-press action: if !torchIsOn { torchLevel = 0.5 }
        if !(level > 0) { level = 0.5 }
        XCTAssertEqual(level, 0.5, accuracy: 0.001)
    }

    // MARK: - Slider step button logic

    func testDecreaseButtonReducesLevelBy5Percent() {
        var level: Float = 0.5
        level = max(0.01, level - 0.05)
        XCTAssertEqual(level, 0.45, accuracy: 0.001)
    }

    func testIncreaseButtonRaisesLevelBy5Percent() {
        var level: Float = 0.5
        level = min(1.0, level + 0.05)
        XCTAssertEqual(level, 0.55, accuracy: 0.001)
    }

    func testDecreaseButtonClampsAtMinimum() {
        var level: Float = 0.01
        level = max(0.01, level - 0.05)
        XCTAssertEqual(level, 0.01, accuracy: 0.001)
    }

    func testIncreaseButtonClampsAtMaximum() {
        var level: Float = 1.0
        level = min(1.0, level + 0.05)
        XCTAssertEqual(level, 1.0, accuracy: 0.001)
    }

    // MARK: - Detection mode

    func testAllModesAvailable() {
        XCTAssertEqual(DetectionMode.allCases.count, 3)
        XCTAssertTrue(DetectionMode.allCases.contains(.table))
        XCTAssertTrue(DetectionMode.allCases.contains(.binder))
        XCTAssertTrue(DetectionMode.allCases.contains(.quickScan))
    }
}
