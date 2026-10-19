import UIKit
import XCTest
@testable import MTGScannerKit

@MainActor
final class FlashlightButtonTests: XCTestCase {
    func testTouchDownDoesNotChangeBrightnessAndTapSelectsNearestPresetOnce() {
        let bar = BrightnessBarControl()
        bar.frame.size = CGSize(width: 300, height: 44)
        bar.level = 0.48
        var values: [Float] = []
        var haptics = 0
        bar.onChange = { values.append($0) }
        bar.haptic = { haptics += 1 }
        bar.begin(at: 150)
        XCTAssertEqual(bar.level, 0.48, accuracy: 0.001)
        XCTAssertTrue(values.isEmpty)
        XCTAssertEqual(haptics, 0)
        bar.end(at: 150)
        XCTAssertEqual(bar.level, 0.5, accuracy: 0.001)
        XCTAssertEqual(values, [0.5])
        XCTAssertEqual(haptics, 1)
    }

    func testEachMarkedPresetCommitsOnReleaseWithOneHaptic() {
        let bar = BrightnessBarControl()
        bar.frame.size = CGSize(width: 300, height: 44)
        var haptics = 0
        bar.haptic = { haptics += 1 }
        for (position, expected) in [(0.0, Float(0.01)), (30, 0.1), (75, 0.25), (150, 0.5), (225, 0.75), (300, 1)] {
            let previous = bar.level
            bar.begin(at: position)
            XCTAssertEqual(bar.level, previous)
            bar.end(at: position)
            XCTAssertEqual(bar.level, expected, accuracy: 0.001)
        }
        XCTAssertEqual(haptics, 6)
    }

    func testRelativeDragUsesOnePercentStepsWithoutSnapOrHaptics() {
        let bar = BrightnessBarControl()
        bar.frame.size = CGSize(width: 300, height: 44)
        bar.level = 0.37
        var haptics = 0
        bar.haptic = { haptics += 1 }
        bar.begin(at: 200)
        bar.move(to: 233)
        XCTAssertEqual(bar.level, 0.48, accuracy: 0.001)
        bar.end(at: 233)
        XCTAssertEqual(bar.level, 0.48, accuracy: 0.001)
        XCTAssertEqual(haptics, 0)
        bar.begin(at: 50)
        bar.move(to: 100)
        bar.move(to: 70)
        bar.end(at: 70)
        XCTAssertEqual(bar.level, 0.55, accuracy: 0.001)
        XCTAssertEqual(haptics, 0)
    }

    func testCancellationDoesNotCommitTapAndDragClampsAtBounds() {
        let bar = BrightnessBarControl()
        bar.frame.size = CGSize(width: 300, height: 44)
        bar.level = 0.48
        var haptics = 0
        bar.haptic = { haptics += 1 }
        bar.begin(at: 10)
        bar.cancel()
        bar.end(at: 10)
        XCTAssertEqual(bar.level, 0.48, accuracy: 0.001)
        bar.begin(at: 200)
        bar.move(to: -400)
        bar.end(at: -400)
        XCTAssertEqual(bar.level, 0.01, accuracy: 0.001)
        bar.begin(at: 10)
        bar.move(to: 900)
        bar.end(at: 900)
        XCTAssertEqual(bar.level, 1, accuracy: 0.001)
        XCTAssertEqual(haptics, 0)
    }

    func testNativeAccessibleAdjustmentAndNamedPresetsUseProductionState() throws {
        let bar = BrightnessBarControl()
        bar.level = 0.48
        var haptics = 0
        bar.haptic = { haptics += 1 }
        XCTAssertTrue(bar.accessibilityTraits.contains(.adjustable))
        bar.accessibilityIncrement()
        XCTAssertEqual(bar.level, 0.49, accuracy: 0.001)
        bar.accessibilityDecrement()
        XCTAssertEqual(bar.level, 0.48, accuracy: 0.001)
        XCTAssertEqual(haptics, 0)
        let actions = try XCTUnwrap(bar.accessibilityCustomActions)
        XCTAssertEqual(actions.map(\.name), [
            "1 percent", "10 percent", "25 percent", "50 percent", "75 percent", "100 percent"
        ])
        XCTAssertTrue(try XCTUnwrap(actions[3].actionHandler)(actions[3]))
        XCTAssertEqual(bar.level, 0.5, accuracy: 0.001)
        XCTAssertEqual(haptics, 1)
    }

    func testRestoreRememberedLevelAndToggleOffPreservesIt() {
        let torch = TorchState(level: 0, remembered: 0.48)
        torch.toggle()
        XCTAssertEqual(torch.level, 0.48, accuracy: 0.001)
        torch.toggle()
        XCTAssertEqual(torch.level, 0)
        XCTAssertEqual(torch.remembered, 0.48, accuracy: 0.001)
        torch.openBrightness()
        XCTAssertEqual(torch.level, 0.48, accuracy: 0.001)
    }
}
