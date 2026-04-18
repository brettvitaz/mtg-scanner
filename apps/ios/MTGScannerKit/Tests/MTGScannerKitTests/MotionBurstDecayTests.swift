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
            referenceDecayTimeout: 0.1
        ))

        // Warm up and trigger burst
        for _ in 0..<6 {
            _ = detector.process(diff: 0.5)
        }

        // In active state, should not decay even with old timestamp
        detector.lastReferenceUpdate = Date(timeIntervalSinceNow: -2.0)
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
