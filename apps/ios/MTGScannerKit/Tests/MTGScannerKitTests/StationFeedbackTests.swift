import UIKit
import XCTest
@testable import MTGScannerKit

@MainActor
final class StationFeedbackTests: XCTestCase {
    func testCompletionWaitsForPreparationAndReleasesGuardBeforeReadiness() async throws {
        let gate = StationCropGate()
        let queue = RecognitionQueue()
        queue.maxConcurrent = 0
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }
        let payload = RecognitionImagePayload.cameraCapture(image: image, data: Data([1]))
        let model = AutoScanViewModel(
            detectorProvider: { nil }, recognitionQueue: queue, capturePhoto: { payload },
            detectBox: { _ in CGRect(x: 0.25, y: 0.2, width: 0.3, height: 0.6) },
            cropImage: { _, _ in await gate.run() }
        )
        var completions = 0
        model.feedback.announce = { [weak model] message, _ in
            guard let model else { XCTFail("Capture model was released before feedback"); return }
            completions += 1
            XCTAssertTrue(message.contains("Ready for the next card"))
            XCTAssertTrue(model.canCaptureManually)
            XCTAssertEqual(model.stationStatus, .ready)
            XCTAssertEqual(queue.pendingCount, 1)
        }
        model.start()
        model.captureManually()
        try await wait { await gate.isWaiting }
        XCTAssertEqual(model.stationStatus, .capturing)
        XCTAssertEqual(completions, 0)
        XCTAssertFalse(model.prepareForZoomChange(from: 1, to: 2))
        await gate.finish(image)
        try await wait { completions == 1 }
        XCTAssertTrue(model.canCaptureManually)
        model.captureDelay = 60
        model.presenceTracker.onNewCardSignal?(CGRect(x: 0.25, y: 0.2, width: 0.3, height: 0.6), model.scanSessionID)
        try await wait { model.captureState == .settling }
        XCTAssertEqual(completions, 1)
        model.stop()
    }

    func testZoomSuspendsSettlingAndAutomaticallyResumesActiveDetection() async throws {
        let model = AutoScanViewModel(detector: nil)
        model.captureDelay = 60
        model.start()
        let oldSession = model.scanSessionID
        model.presenceTracker.onNewCardSignal?(CGRect(x: 0.25, y: 0.2, width: 0.3, height: 0.6), oldSession)
        try await wait { model.captureState == .settling }
        XCTAssertTrue(model.prepareForZoomChange(from: 1, to: 1))
        XCTAssertTrue(model.isActive)
        XCTAssertTrue(model.prepareForZoomChange(from: 1, to: 1.5))
        XCTAssertTrue(model.isActive)
        model.isZoomMoving = true
        XCTAssertEqual(model.stationStatus, .paused)
        XCTAssertFalse(model.isCalibrated)
        let pausedSession = model.scanSessionID
        XCTAssertTrue(model.prepareForZoomChange(from: 1.5, to: 1.8))
        XCTAssertEqual(model.scanSessionID, pausedSession)
        model.presenceTracker.onNewCardSignal?(CGRect(x: 0.25, y: 0.2, width: 0.3, height: 0.6), pausedSession)
        await Task.yield()
        XCTAssertEqual(model.captureState, .watching)
        model.isZoomMoving = false
        XCTAssertTrue(model.isActive)
        XCTAssertEqual(model.stationStatus, .ready)
        model.presenceTracker.onNewCardSignal?(CGRect(x: 0.25, y: 0.2, width: 0.3, height: 0.6), oldSession)
        await Task.yield()
        XCTAssertEqual(model.captureState, .watching)
        model.stop()
    }

    func testFailedCaptureDoesNotCompleteOrIndicateReady() async throws {
        let model = AutoScanViewModel(detector: nil)
        var completions = 0
        model.feedback.announce = { _, _ in completions += 1 }
        model.captureFocusedPhoto = { _ in .failure(.unavailable) }
        model.start()
        model.captureManually()
        try await wait { model.canCaptureManually }
        XCTAssertEqual(completions, 0)
        XCTAssertNotNil(model.captureFailure)
        XCTAssertNotEqual(model.stationStatus, .ready)
        model.presenceTracker.onNewCardSignal?(CGRect(x: 0.25, y: 0.2, width: 0.3, height: 0.6), model.scanSessionID)
        await Task.yield()
        XCTAssertEqual(model.captureState, .watching)
        model.stop()
    }

    func testManualWhileStoppedCompletesWithoutAutomaticReadiness() async throws {
        let model = AutoScanViewModel(detector: nil)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }
        model.captureFocusedPhoto = { _ in .success(.cameraCapture(image: image, data: Data([1]))) }
        var readyEvents: [Bool] = []
        model.feedback.announce = { message, _ in readyEvents.append(message.contains("Ready for the next card")) }
        model.recognitionQueue.maxConcurrent = 0
        model.captureManually()
        try await wait { readyEvents.count == 1 }
        XCTAssertEqual(readyEvents, [false])
        XCTAssertEqual(model.stationStatus, .stopped)
    }

    private func wait(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Station did not reach expected state")
    }
}

private actor StationCropGate {
    private var continuation: CheckedContinuation<CardCropResult, Never>?
    var isWaiting: Bool { continuation != nil }
    func run() async -> CardCropResult { await withCheckedContinuation { continuation = $0 } }
    func finish(_ image: UIImage) {
        continuation?.resume(returning: CardCropResult(crops: [image], detectedCount: 1))
        continuation = nil
    }
}
