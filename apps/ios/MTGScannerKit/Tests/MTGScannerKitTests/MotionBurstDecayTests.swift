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

        // Update to a shorter timeout and wait
        detector.configuration.referenceDecayTimeout = 0.1
        Thread.sleep(forTimeInterval: 0.15)

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

        // In active state, should not decay even after timeout
        Thread.sleep(forTimeInterval: 0.15)
        XCTAssertFalse(detector.shouldDecayReference())
    }

    func testMarkReferenceUpdatedResetsTimer() {
        var detector = MotionBurstDetector(configuration: MotionBurstConfiguration(
            referenceDecayTimeout: 0.1
        ))

        Thread.sleep(forTimeInterval: 0.05)
        detector.markReferenceUpdated()
        Thread.sleep(forTimeInterval: 0.07)

        // Should not decay because timer was reset
        XCTAssertFalse(detector.shouldDecayReference())
    }
}
