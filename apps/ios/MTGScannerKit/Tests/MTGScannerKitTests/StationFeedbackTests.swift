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
        model.presenceTracker.onReadinessChanged?(true, model.scanSessionID)
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
        XCTAssertEqual(model.stationStatus, .paused)
        try await wait { !model.isPausedForZoom }
        XCTAssertEqual(model.stationStatus, .preparing)
        model.presenceTracker.onReadinessChanged?(true, model.scanSessionID)
        XCTAssertEqual(model.stationStatus, .ready)
        model.presenceTracker.onNewCardSignal?(CGRect(x: 0.25, y: 0.2, width: 0.3, height: 0.6), oldSession)
        await Task.yield()
        XCTAssertEqual(model.captureState, .watching)
        model.stop()
    }

    func testPostZoomPauseRejectsSignalsThenRearmsWithAFreshSession() async throws {
        let model = AutoScanViewModel(detector: nil)
        model.captureDelay = 60
        model.start()
        XCTAssertTrue(model.prepareForZoomChange(from: 1, to: 2))
        model.isZoomMoving = true
        model.isZoomMoving = false
        let settlingSession = model.scanSessionID
        let ended = ContinuousClock.now
        XCTAssertEqual(model.stationStatus, .paused)
        XCTAssertTrue(model.canCaptureManually)
        model.presenceTracker.onNewCardSignal?(CGRect(x: 0.25, y: 0.2, width: 0.3, height: 0.6), settlingSession)
        await Task.yield()
        XCTAssertEqual(model.captureState, .watching)
        try await wait { !model.isPausedForZoom }
        XCTAssertEqual(model.stationStatus, .preparing)
        model.presenceTracker.onReadinessChanged?(true, model.scanSessionID)
        XCTAssertEqual(model.stationStatus, .ready)
        XCTAssertGreaterThanOrEqual(ended.duration(to: .now), .milliseconds(700))
        XCTAssertNotEqual(model.scanSessionID, settlingSession)
        model.presenceTracker.onNewCardSignal?(CGRect(x: 0.25, y: 0.2, width: 0.3, height: 0.6), settlingSession)
        await Task.yield()
        XCTAssertEqual(model.captureState, .watching)
        model.presenceTracker.onNewCardSignal?(CGRect(x: 0.25, y: 0.2, width: 0.3, height: 0.6), model.scanSessionID)
        try await wait { model.captureState == .settling }
        model.stop()
    }

    func testAnotherZoomRestartsThePauseAndStopCancelsIt() async throws {
        let model = AutoScanViewModel(detector: nil)
        model.start()
        model.isZoomMoving = true
        model.isZoomMoving = false
        // A second user gesture arrives before the first post-zoom pause ends.
        try await Task.sleep(for: .milliseconds(300))
        model.isZoomMoving = true
        model.isZoomMoving = false
        let ended = ContinuousClock.now
        XCTAssertEqual(model.stationStatus, .paused)
        try await wait { !model.isPausedForZoom }
        XCTAssertEqual(model.stationStatus, .preparing)
        model.presenceTracker.onReadinessChanged?(true, model.scanSessionID)
        XCTAssertEqual(model.stationStatus, .ready)
        XCTAssertGreaterThanOrEqual(ended.duration(to: .now), .milliseconds(700))
        model.isZoomMoving = true
        model.isZoomMoving = false
        model.stop()
        XCTAssertFalse(model.isPausedForZoom)
        XCTAssertEqual(model.stationStatus, .stopped)
        model.start()
        XCTAssertEqual(model.stationStatus, .preparing)
        model.stop()
    }

    func testManualPhotoAcceptedDuringPostZoomPauseSurvivesTheOldPauseDeadline() async throws {
        let gate = StationCropGate()
        let queue = RecognitionQueue()
        queue.maxConcurrent = 0
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }
        let model = AutoScanViewModel(
            detectorProvider: { nil }, recognitionQueue: queue,
            capturePhoto: { .cameraCapture(image: image, data: Data([1])) },
            detectBox: { _ in CGRect(x: 0.25, y: 0.2, width: 0.3, height: 0.6) },
            cropImage: { _, _ in await gate.run() }
        )
        model.start()
        model.isZoomMoving = true
        model.isZoomMoving = false
        XCTAssertEqual(model.stationStatus, .paused)
        model.captureManually()
        try await wait { await gate.isWaiting }
        // This photo-service double has no video stream; integration tests exercise real rearming samples.
        model.presenceTracker.onReadinessChanged?(true, model.scanSessionID)
        // The accepted crop deliberately completes after the cancelled pause's deadline.
        try await Task.sleep(for: .milliseconds(900))
        await gate.finish(image)
        try await wait { queue.pendingCount == 1 && model.canCaptureManually }
        XCTAssertNotNil(model.lastCroppedImage)
        XCTAssertEqual(model.stationStatus, .ready)
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

    func testStaleReadinessCannotArmANewSession() {
        let model = AutoScanViewModel(detector: nil)
        model.start()
        let previous = model.scanSessionID
        model.stop()
        model.start()
        XCTAssertEqual(model.stationStatus, .preparing)
        model.presenceTracker.onReadinessChanged?(true, previous)
        XCTAssertEqual(model.stationStatus, .preparing)
        model.presenceTracker.onReadinessChanged?(true, model.scanSessionID)
        XCTAssertEqual(model.stationStatus, .ready)
        model.stop()
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
