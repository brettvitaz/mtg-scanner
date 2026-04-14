import XCTest
@testable import MTGScannerKit

/// Tests for MotionBurstDetector peak threshold functionality.
final class MotionBurstPeakTests: XCTestCase {

    func testShadowWithoutPeakIsRejected() {
        // Simulate shadow: gradual rise to medium diff, no sharp peak
        var detector = MotionBurstDetector(configuration: MotionBurstConfiguration(
            burstFrameCount: 2,
            burstWindowSize: 4,
            settlementFrames: 2,
            motionThreshold: 0.015,
            maxHoverDuration: 3,  // Short hover to trigger reset quickly
            minPeakThreshold: 0.05  // Require sharp peak
        ))

        // Warm up
        for _ in 0..<4 {
            _ = detector.process(diff: 0.01)
        }

        // Gradual rise (shadow pattern) - max diff 0.03, below peak threshold
        _ = detector.process(diff: 0.02)
        _ = detector.process(diff: 0.025)

        // Continue with varying diffs to trigger hover timeout
        // Need > maxHoverDuration * 3 frames to force reset
        for i in 0..<12 {
            _ = detector.process(diff: 0.03 + Float(i % 3) * 0.005)
        }

        // Should NOT have triggered capture - shadow was rejected
        // State should be idle after hover baseline reset
        XCTAssertEqual(detector.state, .idle)
    }

    func testCardWithPeakTriggers() {
        // Simulate card: sharp spike to high diff
        var detector = MotionBurstDetector(configuration: MotionBurstConfiguration(
            burstFrameCount: 2,
            burstWindowSize: 4,
            settlementFrames: 2,
            motionThreshold: 0.015,
            minPeakThreshold: 0.05  // Require sharp peak
        ))

        // Warm up
        for _ in 0..<4 {
            _ = detector.process(diff: 0.01)
        }

        // Sharp spike (card pattern) - peak at 0.08, above threshold
        _ = detector.process(diff: 0.08)  // spike
        _ = detector.process(diff: 0.06)  // still high

        // Settlement with card in frame
        _ = detector.process(diff: 0.055)
        let triggered = detector.process(diff: 0.053)

        // SHOULD trigger because we had a sharp peak
        XCTAssertTrue(triggered)
        XCTAssertEqual(detector.state, .settled)
    }

    func testLightChangeWithoutPeakIsRejected() {
        // Simulate light change: step change to sustained diff
        var detector = MotionBurstDetector(configuration: MotionBurstConfiguration(
            burstFrameCount: 3,
            burstWindowSize: 5,
            settlementFrames: 2,
            motionThreshold: 0.015,
            maxHoverDuration: 3,  // Short hover to trigger reset quickly
            minPeakThreshold: 0.05
        ))

        // Warm up
        for _ in 0..<5 {
            _ = detector.process(diff: 0.01)
        }

        // Step change (light turned on) - sustained at 0.04, no peak
        _ = detector.process(diff: 0.035)
        _ = detector.process(diff: 0.038)
        _ = detector.process(diff: 0.04)

        // Continue with varying diffs to trigger hover timeout
        // Need > maxHoverDuration * 3 frames to force reset
        for i in 0..<12 {
            _ = detector.process(diff: 0.04 + Float(i % 3) * 0.005)
        }

        // Should NOT have triggered capture - light change was rejected
        XCTAssertEqual(detector.state, .idle)
    }
}
