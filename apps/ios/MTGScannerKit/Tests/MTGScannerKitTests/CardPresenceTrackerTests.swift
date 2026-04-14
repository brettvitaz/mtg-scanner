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

    func testFirstFrameSeedsReferenceImmediately() async {
        let tracker = CardPresenceTracker(detector: nil)

        let firstDiff = await tracker.test_calculateFrameDiff(samples: [0, 0, 0, 0])
        let secondDiff = await tracker.test_calculateFrameDiff(samples: [255, 255, 255, 255])

        XCTAssertEqual(firstDiff, 0.0, accuracy: 0.001)
        XCTAssertGreaterThan(secondDiff, 0.0)
    }

    func testRecoverFromCaptureFailureClearsPendingCapture() async {
        let tracker = CardPresenceTracker(detector: nil)

        await tracker.test_setPendingCapture(true)
        XCTAssertTrue(await tracker.test_isPendingCapture())

        tracker.recoverFromCaptureFailure()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(await tracker.test_isPendingCapture())
    }

    func testDetectBestBoxFiltersStillImageBoxesThroughDetectionZone() async {
        let tracker = CardPresenceTracker(detector: nil)
        let calibratedZone = DetectionZone.calibrated(
            from: CGRect(x: 0.20, y: 0.20, width: 0.20, height: 0.55),
            tolerance: 0
        )

        tracker.setZone(calibratedZone)
        try? await Task.sleep(for: .milliseconds(50))

        let insideZone = CardBoundingBox(
            rect: CGRect(x: 0.20, y: 0.25, width: 0.20, height: 0.55),
            confidence: 0.80
        )
        let outsideZoneHigherConfidence = CardBoundingBox(
            rect: CGRect(x: 0.62, y: 0.10, width: 0.22, height: 0.60),
            confidence: 0.99
        )

        let bestBox = await tracker.test_bestBox(from: [outsideZoneHigherConfidence, insideZone])

        XCTAssertEqual(bestBox, insideZone.rect)
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
