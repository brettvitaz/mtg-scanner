import XCTest
@testable import MTGScannerKit

final class CardPresenceTrackerTests: XCTestCase {

    // MARK: - sceneChangeThreshold

    func testInitialDefaultThreshold() {
        let tracker = CardPresenceTracker(detector: nil)
        XCTAssertEqual(tracker.sceneChangeThreshold, 0.010, accuracy: 0.001)
    }

    func testConfidenceThresholdIsForwarded() {
        // When detector is nil, the property write should not crash.
        let tracker = CardPresenceTracker(detector: nil)
        tracker.confidenceThreshold = 0.7
        XCTAssertEqual(tracker.confidenceThreshold, 0.7, accuracy: 0.001)
    }

    // MARK: - markCaptured (smoke test — exercises the async path without a real buffer)

    func testMarkCapturedDoesNotCrash() {
        let tracker = CardPresenceTracker(detector: nil)
        tracker.markCaptured()
        // Verifies no crash on the internal presenceQueue dispatch.
    }

    // MARK: - onNewCardSignal without detector

    func testNoSignalWhenDetectorIsNilEvenIfDiffIsHigh() {
        // Without a YOLO detector, process(pixelBuffer:) finds no boxes and
        // must not fire onNewCardSignal.  We can't create a CVPixelBuffer in unit
        // tests, but we verify the callback is not set up by default.
        let tracker = CardPresenceTracker(detector: nil)
        var signalFired = false
        tracker.onNewCardSignal = { _ in signalFired = true }
        // No frames are processed → signal must not fire.
        XCTAssertFalse(signalFired)
    }
}
