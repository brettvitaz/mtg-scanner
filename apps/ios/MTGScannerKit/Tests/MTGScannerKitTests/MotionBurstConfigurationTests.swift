import XCTest
@testable import MTGScannerKit

/// Tests for MotionBurstConfiguration presets and validation.
final class MotionBurstConfigurationTests: XCTestCase {

    func testBalancedPreset() {
        let config = MotionBurstConfiguration.balanced
        XCTAssertEqual(config.burstFrameCount, 2)
        XCTAssertEqual(config.burstWindowSize, 8)
        XCTAssertEqual(config.settlementFrames, 2)
        XCTAssertEqual(config.motionThreshold, 0.010, accuracy: 0.001)
        XCTAssertEqual(config.minPeakThreshold, 0.05, accuracy: 0.001)
    }

    func testFastPreset() {
        let config = MotionBurstConfiguration.fast
        XCTAssertEqual(config.burstFrameCount, 2)
        XCTAssertEqual(config.burstWindowSize, 6)
        XCTAssertEqual(config.settlementFrames, 2)
        XCTAssertEqual(config.motionThreshold, 0.010, accuracy: 0.001)
        XCTAssertEqual(config.minPeakThreshold, 0.04, accuracy: 0.001)
    }

    func testConservativePreset() {
        let config = MotionBurstConfiguration.conservative
        XCTAssertEqual(config.burstFrameCount, 3)
        XCTAssertEqual(config.burstWindowSize, 10)
        XCTAssertEqual(config.settlementFrames, 3)
        XCTAssertEqual(config.motionThreshold, 0.012, accuracy: 0.001)
        XCTAssertEqual(config.minPeakThreshold, 0.08, accuracy: 0.001)
    }

    func testConfigurationValidationAdjustsWindowSize() {
        var config = MotionBurstConfiguration(
            burstFrameCount: 8,
            burstWindowSize: 8  // Too small
        )
        config.validate()
        XCTAssertGreaterThanOrEqual(config.burstWindowSize, config.burstFrameCount + 2)
    }

    func testConfigurationBounds() {
        let config = MotionBurstConfiguration(
            burstFrameCount: 100,  // Should clamp to 8
            burstWindowSize: 1,    // Should clamp to 4
            settlementFrames: 100, // Should clamp to 6
            motionThreshold: 5.0,  // Should clamp to 0.10
            maxHoverDuration: 1,   // Should clamp to 5
            minPeakThreshold: 0.5  // Should clamp to 0.20
        )

        XCTAssertEqual(config.burstFrameCount, 8)
        XCTAssertEqual(config.burstWindowSize, 4)
        XCTAssertEqual(config.settlementFrames, 6)
        XCTAssertEqual(config.motionThreshold, 0.10, accuracy: 0.001)
        XCTAssertEqual(config.maxHoverDuration, 5)
        XCTAssertEqual(config.minPeakThreshold, 0.20, accuracy: 0.001)
    }
}
