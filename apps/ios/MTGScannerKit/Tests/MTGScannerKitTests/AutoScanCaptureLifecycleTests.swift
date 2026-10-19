import UIKit
import XCTest
@testable import MTGScannerKit

@MainActor
final class AutoScanCaptureLifecycleTests: XCTestCase {
    private let box = CGRect(x: 0.25, y: 0.2, width: 0.3, height: 0.6)

    func testManualCaptureWhileStoppedEnqueuesWithoutStartingOrCalibrating() async throws {
        let queue = makeQueue()
        let camera = SuspendedPhotoCapture()
        let vm = makeViewModel(queue: queue, camera: camera)
        vm.captureManually()
        XCTAssertFalse(vm.canCaptureManually)
        try await waitForPhoto(camera)
        camera.finish(makePayload())
        try await waitForCapture(vm)
        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertFalse(vm.isActive)
        XCTAssertFalse(vm.isCalibrated)
        XCTAssertNil(vm.detectionZone)
        XCTAssertEqual(vm.captureState, .watching)
        XCTAssertTrue(vm.statusMessage.contains("Tap Start"))
    }

    func testManualCaptureWhileWatchingResumesAndAcceptsNextCard() async throws {
        let camera = SuspendedPhotoCapture()
        let vm = makeViewModel(queue: makeQueue(), camera: camera)
        vm.start()
        vm.captureManually()
        try await waitForPhoto(camera)
        camera.finish(makePayload())
        try await waitForCapture(vm)
        XCTAssertTrue(vm.isActive)
        XCTAssertEqual(vm.captureState, .watching)
        vm.captureDelay = 60
        vm.presenceTracker.onNewCardSignal?(box, vm.scanSessionID)
        try await waitUntil("Card did not enter settling") { vm.captureState == .settling }
        XCTAssertEqual(vm.captureState, .settling)
        vm.stop()
    }

    func testManualCaptureOverridesSettlingAndRepeatedTapsCaptureOnce() async throws {
        let camera = SuspendedPhotoCapture()
        let vm = makeViewModel(queue: makeQueue(), camera: camera)
        vm.captureDelay = 60
        vm.start()
        vm.presenceTracker.onNewCardSignal?(box, vm.scanSessionID)
        try await waitUntil("Card did not enter settling") { vm.captureState == .settling }
        XCTAssertEqual(vm.captureState, .settling)
        vm.captureManually()
        vm.captureManually()
        try await waitForPhoto(camera)
        XCTAssertEqual(vm.captureState, .capturing)
        XCTAssertEqual(camera.callCount, 1)
        camera.finish(makePayload())
        try await waitForCapture(vm)
        XCTAssertEqual(camera.callCount, 1)
        vm.stop()
    }

    func testStopRestartDiscardsOutstandingPhotoAndHoldsCaptureLock() async throws {
        let queue = makeQueue()
        let camera = SuspendedPhotoCapture()
        let vm = makeViewModel(queue: queue, camera: camera)
        vm.start()
        vm.captureManually()
        try await waitForPhoto(camera)
        vm.stop()
        vm.start()
        let restartedStatus = vm.statusMessage
        vm.captureManually()
        XCTAssertFalse(vm.canCaptureManually)
        XCTAssertEqual(camera.callCount, 1)
        camera.finish(makePayload())
        try await waitForCapture(vm)
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertNil(vm.lastCroppedImage)
        XCTAssertNil(vm.detectionZone)
        XCTAssertEqual(vm.statusMessage, restartedStatus)
        XCTAssertTrue(vm.isActive)
        vm.captureManually()
        try await waitForPhoto(camera)
        camera.finish(makePayload())
        try await waitForCapture(vm)
        XCTAssertEqual(queue.pendingCount, 1)
        vm.stop()
    }

    func testOldSignalCannotSettleRestartedSessionAndStartIsIdempotent() async throws {
        let vm = AutoScanViewModel(detector: nil)
        let unexpectedCapture = expectation(description: "Old signal must not capture")
        unexpectedCapture.isInverted = true
        vm.captureDelay = 0
        vm.captureFocusedPhoto = { _ in
            unexpectedCapture.fulfill()
            return .failure(.unavailable)
        }
        vm.start()
        let oldSession = vm.scanSessionID
        vm.stop()
        vm.start()
        let newSession = vm.scanSessionID
        vm.start()
        XCTAssertEqual(vm.scanSessionID, newSession)
        vm.presenceTracker.onNewCardSignal?(box, oldSession)
        await fulfillment(of: [unexpectedCapture], timeout: 0.05)
        XCTAssertEqual(vm.captureState, .watching)
        vm.captureDelay = 60
        vm.presenceTracker.onNewCardSignal?(box, newSession)
        try await waitUntil("Card did not enter settling") { vm.captureState == .settling }
        XCTAssertEqual(vm.captureState, .settling)
        vm.stop()
    }

    func testFailedManualCaptureCanBeRetriedWhileStopped() async throws {
        let queue = makeQueue()
        let camera = SuspendedPhotoCapture()
        let vm = makeViewModel(queue: queue, camera: camera)
        vm.captureManually()
        try await waitForPhoto(camera)
        camera.finish(nil)
        try await waitForCapture(vm)
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertTrue(vm.statusMessage.contains("retry"))
        XCTAssertFalse(vm.isActive)
        vm.captureManually()
        try await waitForPhoto(camera)
        camera.finish(makePayload())
        try await waitForCapture(vm)
        XCTAssertEqual(queue.pendingCount, 1)
    }

    func testStopRestartDuringCropDiscardsCalibrationPreviewAndRecognition() async throws {
        let queue = makeQueue()
        let crop = SuspendedCrop()
        let payload = makePayload()
        let detectedBox = box
        let vm = AutoScanViewModel(
            detectorProvider: { nil }, recognitionQueue: queue,
            capturePhoto: { payload }, detectBox: { _ in detectedBox },
            cropImage: { _, _ in await crop.run() }
        )
        vm.start()
        vm.captureManually()
        try await waitUntil("Crop did not start") { await crop.hasStarted }
        vm.stop()
        vm.start()
        await crop.finish(payload.displayImage)
        try await waitForCapture(vm)
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertNil(vm.lastCroppedImage)
        XCTAssertFalse(vm.isCalibrated)
        XCTAssertNil(vm.detectionZone)
        XCTAssertEqual(vm.statusMessage, "Watching for cards…")
        vm.stop()
    }

    func testManualCaptureUsesCropAndCalibratesOnlyWhileActive() async throws {
        let queue = makeQueue()
        let payload = makePayload()
        let detectedBox = box
        let vm = AutoScanViewModel(
            detectorProvider: { nil }, recognitionQueue: queue,
            capturePhoto: { payload }, detectBox: { _ in detectedBox },
            cropImage: { image, hint in
                XCTAssertEqual(hint?.yoloBoxTopLeft, detectedBox)
                return CardCropResult(crops: [image], detectedCount: 1)
            }
        )
        vm.start()
        vm.captureManually()
        try await waitForCapture(vm)
        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertNotNil(vm.lastCroppedImage)
        XCTAssertTrue(vm.isCalibrated)
        XCTAssertEqual(vm.detectionZone, DetectionZone.calibrated(fromYOLO: box))
        vm.stop()
    }

    func testStoppedManualCaptureUsesCropWithoutCalibration() async throws {
        let queue = makeQueue()
        let payload = makePayload()
        let detectedBox = box
        let vm = AutoScanViewModel(
            detectorProvider: { nil }, recognitionQueue: queue,
            capturePhoto: { payload }, detectBox: { _ in detectedBox },
            cropImage: { image, _ in CardCropResult(crops: [image], detectedCount: 1) }
        )
        vm.captureManually()
        try await waitForCapture(vm)
        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertNotNil(vm.lastCroppedImage)
        XCTAssertFalse(vm.isCalibrated)
        XCTAssertNil(vm.detectionZone)
        XCTAssertFalse(vm.isActive)
    }

    func testRestartedAutomaticSignalCapturesOnceAfterDelay() async throws {
        let queue = makeQueue()
        let camera = SuspendedPhotoCapture()
        let vm = makeViewModel(queue: queue, camera: camera)
        vm.captureDelay = 0
        vm.start()
        vm.presenceTracker.onNewCardSignal?(box, vm.scanSessionID)
        vm.stop()
        vm.start()
        vm.presenceTracker.onNewCardSignal?(box, vm.scanSessionID)
        try await waitForPhoto(camera)
        XCTAssertEqual(camera.callCount, 1)
        camera.finish(makePayload())
        try await waitForCapture(vm)
        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertEqual(vm.captureState, .watching)
        vm.stop()
    }

    func testFullPhotoFallbackPreservesOriginalUploadBytes() async throws {
        let payload = makePayload()
        let recognized = expectation(description: "Full photo recognized")
        let queue = RecognitionQueue(
            recognize: { data, _, contentType, _ in
                XCTAssertEqual(data, payload.uploadData)
                XCTAssertEqual(contentType, payload.contentType)
                recognized.fulfill()
                return RecognitionResult(cards: [])
            },
            recognizeBatch: { _, _, _ in
                XCTFail("No card crop: should upload the full photo")
                return RecognitionResult(cards: [])
            }
        )
        let vm = AutoScanViewModel(
            detectorProvider: { nil }, recognitionQueue: queue, capturePhoto: { payload }
        )
        vm.captureManually()
        await fulfillment(of: [recognized], timeout: 1)
        try await waitForCapture(vm)
        XCTAssertFalse(vm.isActive)
    }

    func testFocusConfigurationFailureSkipsUploadAndAllowsManualRetry() async throws {
        let queue = makeQueue()
        let vm = AutoScanViewModel(detectorProvider: { nil }, recognitionQueue: queue)
        vm.captureFocusedPhoto = { _ in .failure(.focusConfigurationFailed) }
        vm.start()
        vm.captureManually()
        try await waitForCapture(vm)
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertNil(vm.lastCroppedImage)
        XCTAssertEqual(vm.captureState, .watching)
        XCTAssertTrue(vm.isActive)
        XCTAssertEqual(vm.statusMessage, "Could not configure focus — tap Capture to retry.")
        let payload = makePayload()
        vm.captureFocusedPhoto = { _ in .success(payload) }
        vm.captureManually()
        try await waitForCapture(vm)
        XCTAssertEqual(queue.pendingCount, 1)
        vm.stop()
    }

    func testSignalTargetsCardAndResetClearsFocusPoint() async throws {
        let queue = makeQueue()
        let vm = AutoScanViewModel(detectorProvider: { nil }, recognitionQueue: queue)
        vm.captureDelay = 0
        let focused = expectation(description: "Capture receives the detected card focus point")
        vm.captureFocusedPhoto = { point in
            XCTAssertEqual(point?.x ?? 0, 0.4, accuracy: 0.001)
            XCTAssertEqual(point?.y ?? 0, 0.5, accuracy: 0.001)
            focused.fulfill()
            return .failure(.focusConfigurationFailed)
        }
        vm.start()
        vm.presenceTracker.onNewCardSignal?(box, vm.scanSessionID)
        await fulfillment(of: [focused], timeout: 1)
        try await waitForCapture(vm)
        XCTAssertNotNil(vm.captureFocusPoint)
        vm.stop()
        XCTAssertNil(vm.captureFocusPoint)
        XCTAssertNil(vm.detectionZone)
        XCTAssertFalse(vm.isCalibrated)
    }

    private func makeViewModel(queue: RecognitionQueue, camera: SuspendedPhotoCapture) -> AutoScanViewModel {
        AutoScanViewModel(
            detectorProvider: { nil }, recognitionQueue: queue,
            capturePhoto: { await camera.capture() }
        )
    }

    private func makeQueue() -> RecognitionQueue {
        let queue = RecognitionQueue(
            recognize: { _, _, _, _ in RecognitionResult(cards: []) },
            recognizeBatch: { _, _, _ in RecognitionResult(cards: []) }
        )
        queue.maxConcurrent = 0
        return queue
    }

    private func makePayload() -> RecognitionImagePayload {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        return .cameraCapture(image: image, data: Data([0xFF, 0xD8, 0xFF, 0xD9]))
    }

    private func waitForPhoto(_ camera: SuspendedPhotoCapture) async throws {
        try await waitUntil("Photo capture did not start") { camera.isWaiting }
    }

    private func waitForCapture(_ vm: AutoScanViewModel) async throws {
        try await waitUntil("Capture did not complete") { vm.canCaptureManually }
    }

    private func waitUntil(_ message: String, condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw WaitTimeout(message: message)
    }
}

// MARK: - Navigation lifecycle

extension AutoScanCaptureLifecycleTests {
    func testNavigationPauseFinishesPhotoWithoutRestartingScanning() async throws {
        let queue = makeQueue()
        let camera = SuspendedPhotoCapture()
        let vm = makeViewModel(queue: queue, camera: camera)
        vm.start()
        vm.captureManually()
        try await waitForPhoto(camera)
        vm.feedback.announce = { _, _ in XCTFail("Navigation must not announce automatic readiness") }
        vm.pauseForNavigation()
        vm.pauseForNavigation()
        camera.finish(makePayload())
        try await waitForCapture(vm)
        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertFalse(vm.isActive)
        XCTAssertNil(vm.lastCroppedImage)
        XCTAssertFalse(vm.isCalibrated)
    }

    func testNavigationPauseDuringCropPreservesUploadAcrossRestart() async throws {
        let queue = makeQueue()
        let crop = SuspendedCrop()
        let payload = makePayload()
        let detectedBox = box
        let vm = AutoScanViewModel(
            detectorProvider: { nil }, recognitionQueue: queue,
            capturePhoto: { payload }, detectBox: { _ in
                // Detection can finish well after the test task has yielded many times.
                try? await Task.sleep(for: .milliseconds(500))
                return detectedBox
            },
            cropImage: { _, _ in await crop.run() }
        )
        vm.start()
        vm.captureManually()
        try await waitUntil("Crop did not start") { await crop.hasStarted }
        vm.pauseForNavigation()
        vm.start()
        await crop.finish(payload.displayImage)
        try await waitForCapture(vm)
        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertNil(vm.lastCroppedImage)
        XCTAssertFalse(vm.isCalibrated)
        XCTAssertEqual(vm.statusMessage, "Watching for cards…")
        vm.stop()
    }

    func testNavigationPauseCancelsSettlingWithoutTakingPhoto() async throws {
        let camera = SuspendedPhotoCapture()
        let vm = makeViewModel(queue: makeQueue(), camera: camera)
        vm.captureDelay = 60
        vm.start()
        vm.presenceTracker.onNewCardSignal?(box, vm.scanSessionID)
        try await waitUntil("Card did not enter settling") { vm.captureState == .settling }
        XCTAssertEqual(vm.captureState, .settling)
        vm.pauseForNavigation()
        XCTAssertFalse(vm.isActive)
        XCTAssertEqual(vm.captureState, .watching)
        XCTAssertEqual(camera.callCount, 0)
    }

    func testExplicitStopAfterNavigationDiscardsPreservedPhoto() async throws {
        let queue = makeQueue()
        let camera = SuspendedPhotoCapture()
        let vm = makeViewModel(queue: queue, camera: camera)
        vm.start()
        vm.captureManually()
        try await waitForPhoto(camera)
        vm.pauseForNavigation()
        vm.stop()
        vm.start()
        camera.finish(makePayload())
        try await waitForCapture(vm)
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertNil(vm.lastCroppedImage)
        XCTAssertTrue(vm.isActive)
        vm.stop()
    }

    func testNavigationPauseAllowsAutomaticCaptureTaskToFinish() async throws {
        let queue = makeQueue()
        let camera = SuspendedPhotoCapture()
        let vm = makeViewModel(queue: queue, camera: camera)
        vm.captureDelay = 0
        vm.start()
        vm.presenceTracker.onNewCardSignal?(box, vm.scanSessionID)
        try await waitForPhoto(camera)
        vm.pauseForNavigation()
        camera.finish(makePayload())
        try await waitForCapture(vm)
        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertFalse(vm.isActive)
        XCTAssertNil(vm.lastCroppedImage)
    }

}

@MainActor
private final class SuspendedPhotoCapture {
    private var continuation: CheckedContinuation<RecognitionImagePayload?, Never>?
    private(set) var callCount = 0
    var isWaiting: Bool { continuation != nil }

    func capture() async -> RecognitionImagePayload? {
        callCount += 1
        return await withCheckedContinuation { continuation = $0 }
    }

    func finish(_ payload: RecognitionImagePayload?) {
        continuation?.resume(returning: payload)
        continuation = nil
    }
}

private actor SuspendedCrop {
    private var continuation: CheckedContinuation<CardCropResult, Never>?
    var hasStarted: Bool { continuation != nil }

    func run() async -> CardCropResult {
        await withCheckedContinuation { continuation = $0 }
    }

    func finish(_ image: UIImage) {
        continuation?.resume(returning: CardCropResult(crops: [image], detectedCount: 1))
        continuation = nil
    }
}

private struct WaitTimeout: Error {
    let message: String
}
