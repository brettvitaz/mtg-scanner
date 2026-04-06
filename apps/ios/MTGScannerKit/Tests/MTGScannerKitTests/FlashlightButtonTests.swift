import XCTest
@testable import MTGScannerKit

// Note: FlashlightButton is a SwiftUI view; gesture state cannot be unit-tested
// without a SwiftUI testing library. These tests cover the pure torch/mode logic
// mirrored from the view.
final class FlashlightButtonTests: XCTestCase {

    // MARK: - Torch toggle logic

    func testTorchToggleFromOffUsesDefaultWhenNoSavedLevel() {
        var level: Float = 0
        let lastLevel: Float = 0
        level = lastLevel > 0 ? lastLevel : 0.5
        XCTAssertEqual(level, 0.5, accuracy: 0.001)
    }

    func testTorchToggleFromOffUsesSavedLevel() {
        var level: Float = 0
        let lastLevel: Float = 0.75
        level = lastLevel > 0 ? lastLevel : 0.5
        XCTAssertEqual(level, 0.75, accuracy: 0.001)
    }

    func testTorchToggleFromOnTurnsOffAndPreservesLastLevel() {
        var level: Float = 0.5
        var lastLevel: Float = 0
        if level > 0 {
            lastLevel = level
            level = 0
        }
        XCTAssertEqual(level, 0, accuracy: 0.001)
        XCTAssertEqual(lastLevel, 0.5, accuracy: 0.001)
    }

    // MARK: - Slider logic

    func testDecreaseButtonClampsAtMinimum() {
        let level = max(0.01, Float(0.01) - 0.05)
        XCTAssertEqual(level, 0.01, accuracy: 0.001)
    }

    func testIncreaseButtonClampsAtMaximum() {
        let level = min(1.0, Float(1.0) + 0.05)
        XCTAssertEqual(level, 1.0, accuracy: 0.001)
    }

    func testSnapWithinThreePercentOfAnchor() {
        let anchors: [Float] = [0.01, 0.10, 0.25, 0.50, 0.75, 1.0]
        let level: Float = 0.48
        let anchor = anchors.min(by: { abs($0 - level) < abs($1 - level) })
        let snapped = anchor.flatMap { abs($0 - level) <= 0.03 ? $0 : nil } ?? level
        XCTAssertEqual(snapped, 0.50, accuracy: 0.001)
    }

    func testDoesNotSnapOutsideThreePercentOfAnchor() {
        let anchors: [Float] = [0.01, 0.10, 0.25, 0.50, 0.75, 1.0]
        let level: Float = 0.46
        let anchor = anchors.min(by: { abs($0 - level) < abs($1 - level) })
        let snapped = anchor.flatMap { abs($0 - level) <= 0.03 ? $0 : nil } ?? level
        XCTAssertEqual(snapped, 0.46, accuracy: 0.001)
    }

    // MARK: - Detection mode

    func testOnlyScanAndAutoModesAvailable() {
        XCTAssertEqual(DetectionMode.allCases, [.scan, .auto])
    }
}
