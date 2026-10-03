import UIKit
import XCTest
@testable import MTGScannerKit

@MainActor
final class AutoScanCaptureLifecycleTests: XCTestCase {
    private let box = CGRect(x: 0.25, y: 0.2, width: 0.3, height: 0.6)

    func testManualCaptureWhileStoppedEnqueuesWithoutStartingOrCalibrating() async {
        let queue = makeQueue()
        let camera = SuspendedPhotoCapture()
        let vm = makeViewModel(queue: queue, camera: camera)
        vm.captureManually()
        XCTAssertFalse(vm.canCaptureManually)
        await waitForPhoto(camera)
        camera.finish(makePayload())
        await waitForCapture(vm)
        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertFalse(vm.isActive)
        XCTAssertFalse(vm.isCalibrated)
        XCTAssertNil(vm.detectionZone)
        XCTAssertEqual(vm.captureState, .watching)
        XCTAssertTrue(vm.statusMessage.contains("Tap Start"))
    }

    func testManualCaptureWhileWatchingResumesAndAcceptsNextCard() async {
        let camera = SuspendedPhotoCapture()
        let vm = makeViewModel(queue: makeQueue(), camera: camera)
        vm.start()
        vm.captureManually()
        await waitForPhoto(camera)
        camera.finish(makePayload())
        await waitForCapture(vm)
        XCTAssertTrue(vm.isActive)
        XCTAssertEqual(vm.captureState, .watching)
        vm.captureDelay = 60
        vm.presenceTracker.onNewCardSignal?(box, vm.scanSessionID)
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(vm.captureState, .settling)
        vm.stop()
    }

    func testManualCaptureOverridesSettlingAndRepeatedTapsCaptureOnce() async {
        let camera = SuspendedPhotoCapture()
        let vm = makeViewModel(queue: makeQueue(), camera: camera)
        vm.captureDelay = 0.01
        vm.start()
        vm.presenceTracker.onNewCardSignal?(box, vm.scanSessionID)
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(vm.captureState, .settling)
        vm.captureManually()
        vm.captureManually()
        await waitForPhoto(camera)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(camera.callCount, 1)
        camera.finish(makePayload())
        await waitForCapture(vm)
        XCTAssertEqual(camera.callCount, 1)
        vm.stop()
    }

    func testStopRestartDiscardsOutstandingPhotoAndHoldsCaptureLock() async {
        let queue = makeQueue()
        let camera = SuspendedPhotoCapture()
        let vm = makeViewModel(queue: queue, camera: camera)
        vm.start()
        vm.captureManually()
        await waitForPhoto(camera)
        vm.stop()
        vm.start()
        let restartedStatus = vm.statusMessage
        vm.captureManually()
        XCTAssertFalse(vm.canCaptureManually)
        XCTAssertEqual(camera.callCount, 1)
        camera.finish(makePayload())
        await waitForCapture(vm)
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertNil(vm.lastCroppedImage)
        XCTAssertNil(vm.detectionZone)
        XCTAssertEqual(vm.statusMessage, restartedStatus)
        XCTAssertTrue(vm.isActive)
        vm.captureManually()
        await waitForPhoto(camera)
        camera.finish(makePayload())
        await waitForCapture(vm)
        XCTAssertEqual(queue.pendingCount, 1)
        vm.stop()
    }

    func testOldSignalCannotSettleRestartedSessionAndStartIsIdempotent() async {
        let vm = AutoScanViewModel(detector: nil)
        vm.start()
        let oldSession = vm.scanSessionID
        vm.stop()
        vm.start()
        let newSession = vm.scanSessionID
        vm.start()
        XCTAssertEqual(vm.scanSessionID, newSession)
        vm.presenceTracker.onNewCardSignal?(box, oldSession)
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(vm.captureState, .watching)
        vm.presenceTracker.onNewCardSignal?(box, newSession)
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(vm.captureState, .settling)
        vm.stop()
    }

    func testFailedManualCaptureCanBeRetriedWhileStopped() async {
        let queue = makeQueue()
        let camera = SuspendedPhotoCapture()
        let vm = makeViewModel(queue: queue, camera: camera)
        vm.captureManually()
        await waitForPhoto(camera)
        camera.finish(nil)
        await waitForCapture(vm)
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertTrue(vm.statusMessage.contains("retry"))
        XCTAssertFalse(vm.isActive)
        vm.captureManually()
        await waitForPhoto(camera)
        camera.finish(makePayload())
        await waitForCapture(vm)
        XCTAssertEqual(queue.pendingCount, 1)
    }

    func testStopRestartDuringCropDiscardsCalibrationPreviewAndRecognition() async {
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
        for _ in 0..<1000 {
            if await crop.hasStarted { break }
            await Task.yield()
        }
        let hasStarted = await crop.hasStarted
        XCTAssertTrue(hasStarted)
        vm.stop()
        vm.start()
        await crop.finish(payload.displayImage)
        await waitForCapture(vm)
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertNil(vm.lastCroppedImage)
        XCTAssertFalse(vm.isCalibrated)
        XCTAssertNil(vm.detectionZone)
        XCTAssertEqual(vm.statusMessage, "Watching for cards…")
        vm.stop()
    }

    func testManualCaptureUsesCropAndCalibratesOnlyWhileActive() async {
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
        await waitForCapture(vm)
        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertNotNil(vm.lastCroppedImage)
        XCTAssertTrue(vm.isCalibrated)
        XCTAssertEqual(vm.detectionZone, DetectionZone.calibrated(fromYOLO: box))
        vm.stop()
    }

    func testStoppedManualCaptureUsesCropWithoutCalibration() async {
        let queue = makeQueue()
        let payload = makePayload()
        let detectedBox = box
        let vm = AutoScanViewModel(
            detectorProvider: { nil }, recognitionQueue: queue,
            capturePhoto: { payload }, detectBox: { _ in detectedBox },
            cropImage: { image, _ in CardCropResult(crops: [image], detectedCount: 1) }
        )
        vm.captureManually()
        await waitForCapture(vm)
        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertNotNil(vm.lastCroppedImage)
        XCTAssertFalse(vm.isCalibrated)
        XCTAssertNil(vm.detectionZone)
        XCTAssertFalse(vm.isActive)
    }

    func testRestartedAutomaticSignalCapturesOnceAfterDelay() async {
        let queue = makeQueue()
        let camera = SuspendedPhotoCapture()
        let vm = makeViewModel(queue: queue, camera: camera)
        vm.captureDelay = 0
        vm.start()
        vm.presenceTracker.onNewCardSignal?(box, vm.scanSessionID)
        vm.stop()
        vm.start()
        vm.presenceTracker.onNewCardSignal?(box, vm.scanSessionID)
        await waitForPhoto(camera)
        XCTAssertEqual(camera.callCount, 1)
        camera.finish(makePayload())
        await waitForCapture(vm)
        XCTAssertEqual(queue.pendingCount, 1)
        XCTAssertEqual(vm.captureState, .watching)
        vm.stop()
    }

    func testFullPhotoFallbackPreservesOriginalUploadBytes() async {
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
        await waitForCapture(vm)
        XCTAssertFalse(vm.isActive)
    }

    func testFocusConfigurationFailureSkipsUploadAndAllowsManualRetry() async {
        let queue = makeQueue()
        let vm = AutoScanViewModel(detectorProvider: { nil }, recognitionQueue: queue)
        vm.captureFocusedPhoto = { _ in .failure(.focusConfigurationFailed) }
        vm.start()
        vm.captureManually()
        await waitForCapture(vm)
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertNil(vm.lastCroppedImage)
        XCTAssertEqual(vm.captureState, .watching)
        XCTAssertTrue(vm.isActive)
        XCTAssertEqual(vm.statusMessage, "Could not configure focus — tap Capture to retry.")
        let payload = makePayload()
        vm.captureFocusedPhoto = { _ in .success(payload) }
        vm.captureManually()
        await waitForCapture(vm)
        XCTAssertEqual(queue.pendingCount, 1)
        vm.stop()
    }

    func testSignalTargetsCardAndResetClearsFocusPoint() async {
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
        await waitForCapture(vm)
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

    private func waitForPhoto(_ camera: SuspendedPhotoCapture) async {
        for _ in 0..<1000 {
            if camera.isWaiting { return }
            await Task.yield()
        }
        XCTFail("Photo capture did not start")
    }

    private func waitForCapture(_ vm: AutoScanViewModel) async {
        for _ in 0..<1000 {
            if vm.canCaptureManually { return }
            await Task.yield()
        }
        XCTFail("Capture did not complete")
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
