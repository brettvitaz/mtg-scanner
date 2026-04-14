import XCTest
@testable import MTGScannerKit

/// Tests for core MotionBurstDetector state machine behavior.
final class MotionBurstDetectorTests: XCTestCase {

    // MARK: - Initialization

    func testDefaultConfiguration() {
        let detector = MotionBurstDetector()

        XCTAssertEqual(detector.configuration.burstFrameCount, 3)
        XCTAssertEqual(detector.configuration.burstWindowSize, 5)
        XCTAssertEqual(detector.configuration.settlementFrames, 2)
        XCTAssertEqual(detector.configuration.motionThreshold, 0.015, accuracy: 0.001)
        XCTAssertEqual(detector.configuration.maxHoverDuration, 10)
    }

    func testCustomConfiguration() {
        let config = MotionBurstConfiguration(
            burstFrameCount: 3,
            burstWindowSize: 5,
            settlementFrames: 2,
            motionThreshold: 0.05,
            maxHoverDuration: 8
        )
        let detector = MotionBurstDetector(configuration: config)

        XCTAssertEqual(detector.configuration.burstFrameCount, 3)
        XCTAssertEqual(detector.configuration.burstWindowSize, 5)
        XCTAssertEqual(detector.configuration.settlementFrames, 2)
        XCTAssertEqual(detector.configuration.motionThreshold, 0.05, accuracy: 0.001)
        XCTAssertEqual(detector.configuration.maxHoverDuration, 8)
    }

    // MARK: - State Transitions

    func testInitialStateIsIdle() {
        let detector = MotionBurstDetector()
        XCTAssertEqual(detector.state, .idle)
    }

    func testBurstDetectionRequiresWarmup() {
        var detector = MotionBurstDetector(configuration: MotionBurstConfiguration(
            burstFrameCount: 2,
            burstWindowSize: 4,
            settlementFrames: 2
        ))

        // Before warmup, even high diffs shouldn't trigger
        for _ in 0..<3 {
            let triggered = detector.process(diff: 0.5)
            XCTAssertFalse(triggered)
            XCTAssertEqual(detector.state, .idle)
        }
    }

    func testBurstDetectedAfterWarmup() {
        var detector = MotionBurstDetector(configuration: MotionBurstConfiguration(
            burstFrameCount: 2,
            burstWindowSize: 4,
            settlementFrames: 2
        ))

        // Warm up with low diffs (4 frames, frameIndex goes 0->1->2->3->4)
        for _ in 0..<4 {
            _ = detector.process(diff: 0.01)
        }

        // Now provide burst of high diffs
        // Frame 4: diff=0.5 (1st high frame, not enough for burst)
        // Frame 5: diff=0.5 (2nd high frame, burst detected at frameIndex=6)
        _ = detector.process(diff: 0.5)
        XCTAssertEqual(detector.state, .idle)  // Still warming/not enough frames

        let triggered = detector.process(diff: 0.5)
        XCTAssertFalse(triggered)

        // Burst is detected at frameIndex after processing the 2nd high frame
        XCTAssertEqual(detector.state, .burstDetected(burstStartFrame: 6))
    }

    func testSettlementTriggersCapture() {
        var detector = MotionBurstDetector(configuration: MotionBurstConfiguration(
            burstFrameCount: 2,
            burstWindowSize: 4,
            settlementFrames: 2,
            motionThreshold: 0.3
        ))

        // Warm up
        for _ in 0..<4 {
            _ = detector.process(diff: 0.01)
        }

        // Burst
        _ = detector.process(diff: 0.5)
        _ = detector.process(diff: 0.5)

        // Settlement
        _ = detector.process(diff: 0.01)
        let triggered = detector.process(diff: 0.01)

        XCTAssertTrue(triggered)
        XCTAssertEqual(detector.state, .settled)
    }

    func testHoverTimeout() {
        var detector = MotionBurstDetector(configuration: MotionBurstConfiguration(
            burstFrameCount: 2,
            burstWindowSize: 4,
            settlementFrames: 3,
            motionThreshold: 0.3,
            maxHoverDuration: 5
        ))

        // Warm up (4 frames)
        for _ in 0..<4 {
            _ = detector.process(diff: 0.01)
        }

        // Burst (2 frames to trigger burst, then maxHoverDuration+1 to timeout)
        _ = detector.process(diff: 0.5)  // frame 4
        _ = detector.process(diff: 0.5)  // frame 5 - burst detected at frameIndex=6

        if case .burstDetected(let startFrame) = detector.state {
            XCTAssertEqual(startFrame, 6)
        } else {
            XCTFail("Expected burstDetected state")
        }

        // Continue high motion without settlement (hovering)
        // Vary the diff to avoid triggering stability detection
        // Need to exceed maxHoverDuration (5) from start frame (6)
        // So frameIndex needs to reach 12 (6 + 6)
        for i in 0..<7 {  // 7 more frames to exceed hover duration
            // Vary diff to prevent stability detection (delta > 0.15)
            _ = detector.process(diff: 0.5 + Float(i % 3) * 0.1)
        }

        XCTAssertEqual(detector.state, .hovering(burstStartFrame: 6))
    }

    func testResetClearsState() {
        var detector = MotionBurstDetector()

        // Warm up and trigger burst
        for _ in 0..<10 {
            _ = detector.process(diff: 0.5)
        }

        detector.reset()

        XCTAssertEqual(detector.state, .idle)
        XCTAssertEqual(detector.currentMetrics().consecutiveLowFrames, 0)
    }

    // MARK: - Edge Cases

    func testLowDiffDuringBurstResets() {
        var detector = MotionBurstDetector(configuration: MotionBurstConfiguration(
            burstFrameCount: 2,
            burstWindowSize: 4,
            settlementFrames: 3,
            motionThreshold: 0.3
        ))

        // Warm up
        for _ in 0..<4 {
            _ = detector.process(diff: 0.01)
        }

        // Brief burst
        _ = detector.process(diff: 0.5)

        // Motion stops quickly (not settlement, just removed)
        for _ in 0..<5 {
            _ = detector.process(diff: 0.01)
        }

        // Should return to idle
        XCTAssertEqual(detector.state, .idle)
    }

    func testPartialBurstDoesNotTrigger() {
        var detector = MotionBurstDetector(configuration: MotionBurstConfiguration(
            burstFrameCount: 4,
            burstWindowSize: 6,
            settlementFrames: 2,
            motionThreshold: 0.3
        ))

        // Warm up
        for _ in 0..<6 {
            _ = detector.process(diff: 0.01)
        }

        // Only 3 frames above threshold (need 4)
        _ = detector.process(diff: 0.5)
        _ = detector.process(diff: 0.5)
        _ = detector.process(diff: 0.5)

        // Not enough for burst
        XCTAssertEqual(detector.state, .idle)
    }

    // MARK: - Metrics

    func testMetricsReflectCurrentState() {
        var detector = MotionBurstDetector(configuration: MotionBurstConfiguration(
            burstFrameCount: 2,
            burstWindowSize: 4,
            settlementFrames: 2,
            motionThreshold: 0.3
        ))

        // Warm up (4 frames, frameIndex = 4)
        for _ in 0..<4 {
            _ = detector.process(diff: 0.01)
        }

        var metrics = detector.currentMetrics()
        XCTAssertEqual(metrics.state, .idle)
        XCTAssertEqual(metrics.currentDiff, 0.01, accuracy: 0.001)

        // Burst: frame 4 (index 5), frame 5 (index 6, burst detected)
        _ = detector.process(diff: 0.5)
        _ = detector.process(diff: 0.5)

        metrics = detector.currentMetrics()
        // Burst detected at frameIndex=6
        XCTAssertEqual(metrics.state, .burstDetected(burstStartFrame: 6))
        // After processing frameIndex=6, framesSinceBurstStart = 6 - 6 = 0
        XCTAssertEqual(metrics.framesSinceBurstStart, 0)

        // Process one more frame to advance
        _ = detector.process(diff: 0.5)
        metrics = detector.currentMetrics()
        XCTAssertEqual(metrics.framesSinceBurstStart, 1)
    }

    func testRejectionReasonLogged() {
        var detector = MotionBurstDetector(configuration: MotionBurstConfiguration(
            burstFrameCount: 4,
            burstWindowSize: 6,
            motionThreshold: 0.3
        ))

        // Before warmup
        _ = detector.process(diff: 0.01)
        let metrics = detector.currentMetrics()
        XCTAssertNotNil(metrics.rejectionReason)
        XCTAssertTrue(metrics.rejectionReason?.contains("Warming up") ?? false)
    }
}
