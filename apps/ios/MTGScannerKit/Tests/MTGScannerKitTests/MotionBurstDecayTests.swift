import XCTest
@testable import MTGScannerKit

/// Tests for MotionBurstDetector reference decay functionality.
final class MotionBurstDecayTests: XCTestCase {

    func testReferenceDecayTimeout() {
        var detector = MotionBurstDetector(configuration: MotionBurstConfiguration(
            referenceDecayTimeout: 1.0  // Long timeout for initial state
        ))

        // Initially should not decay
        let firstCheck = detector.shouldDecayReference()
        XCTAssertFalse(firstCheck, "Should not decay immediately after creation")

        // Set the timestamp far enough in the past to trigger decay
        detector.configuration.referenceDecayTimeout = 0.1
        detector.lastReferenceUpdate = Date(timeIntervalSinceNow: -2.0)

        // Should decay after timeout
        let secondCheck = detector.shouldDecayReference()
        XCTAssertTrue(secondCheck, "Should decay after timeout period elapsed")
    }

    func testReferenceDecayDoesNotTriggerWhenActive() {
        var detector = MotionBurstDetector(configuration: MotionBurstConfiguration(
            burstFrameCount: 2,
            burstWindowSize: 4,
            settlementFrames: 3,
            referenceDecayTimeout: 0.1
        ))

        // Warm up: use alternating high/low diff to reach burstDetected state
        // without settling. settlementFrames=3 requires 3 consecutive low/stable
        // frames; alternating prevents that, keeping us in burstDetected.
        _ = detector.process(diff: 0.5)   // frame 0
        _ = detector.process(diff: 0.5)   // frame 1
        _ = detector.process(diff: 0.5)   // frame 2
        _ = detector.process(diff: 0.5)   // frame 3 (warm up complete)
        _ = detector.process(diff: 0.01)  // frame 4 (below threshold → 1 low)
        _ = detector.process(diff: 0.5)   // frame 5 (resets low counter, still burst)

        // In active state, should not decay even with old timestamp
        // Use -10.0 so elapsed (10s) definitively exceeds the clamped timeout (2.0s),
        // ensuring the isActive guard is the only thing blocking decay.
        detector.lastReferenceUpdate = Date(timeIntervalSinceNow: -10.0)
        XCTAssertFalse(detector.shouldDecayReference())
    }

    func testMarkReferenceUpdatedResetsTimer() {
        var detector = MotionBurstDetector(configuration: MotionBurstConfiguration(
            referenceDecayTimeout: 0.1
        ))

        detector.markReferenceUpdated()

        // Should not decay because timer was reset
        XCTAssertFalse(detector.shouldDecayReference())
    }
}
