import SwiftUI
import UIKit
import ViewInspector
import XCTest
@testable import MTGScannerKit

@MainActor
final class CaptureZoomWiringTests: XCTestCase {
    func testHostedSharedPresetControlsReportDeviceClampAndPinchInBothModes() async throws {
        for mode in DetectionMode.allCases { try await exerciseHostedPresetControls(mode) }
    }

    private func completeBaselineLearningAfterZoom(_ model: AutoScanViewModel) async throws {
        try await waitForScanCount { !model.isPausedForZoom }
        XCTAssertEqual(model.stationStatus, .preparing)
        // This camera-device double supplies zoom events, not live frame samples.
        model.presenceTracker.onReadinessChanged?(true, model.scanSessionID)
        XCTAssertEqual(model.stationStatus, .ready)
    }

    private func exerciseHostedPresetControls(_ mode: DetectionMode) async throws {
        let app = AppModel()
        let context = try makeScanCountContext()
        app.modelContext = context
        let model = AutoScanViewModel(detector: nil)
        let detection = CardDetectionViewModel()
        let coordinator = CameraCaptureCoordinator()
        let camera = CameraViewController()
        var applied: [CGFloat] = []
        camera.zoomDevice = immediateZoomDevice(maximum: 2.4) { applied.append($0) }
        let state = CaptureHostState()
        let view = CaptureZoomHost(state: state, mode: mode, model: model, detection: detection,
                                   coordinator: coordinator, camera: camera)
            .environment(app).modelContainer(context.container)
        let window = makeScanCountWindow(view: view)
        defer { closeScanCountWindow(window) }
        try await waitForScanCount { coordinator.controller != nil && model.appModel != nil }
        let control = try view.inspect().find(ZoomPresetControl.self).actualView()
        for (preset, expected) in [(1.5, 1.5), (2, 2), (3, 2.4), (1, 1)] {
            control.onSelect(preset)
            try await waitForScanCount { !camera.isZoomMoving && abs(detection.zoomFactor - expected) < 0.001 }
        }
        XCTAssertTrue(applied.contains { $0 > 1 && $0 < 1.5 })
        camera.applyPinch(scale: 1.73)
        XCTAssertEqual(detection.zoomFactor, 1.73, accuracy: 0.001)
        let refreshed = try view.inspect().find(ZoomPresetControl.self).actualView()
        XCTAssertEqual(ZoomPresetControl.label(refreshed.currentZoom), "1.7×")
        model.start()
        camera.zoomDevice = immediateZoomDevice(maximum: 2.4, accepts: false)
        camera.setZoom(2)
        XCTAssertTrue(model.isActive)
        XCTAssertEqual(detection.zoomFactor, 1.73, accuracy: 0.001)
        try await retryFailedZoom(coordinator, camera: camera, detection: detection)
        model.start()
        state.active = false
        try await waitForScanCount { !model.isActive }
        XCTAssertEqual(detection.zoomFactor, camera.appliedZoom)
        state.active = true
        try await waitForScanCount { camera.appliedZoom == 2 && detection.zoomFactor == 2 }
        XCTAssertFalse(model.isCalibrated)
    }

    // Device motion locks capture; automatic detection stays paused while optics settle afterward.
    func testMotionReportsProgressPausesBeforeMutationAndLocksCaptureUntilCompletion() async throws {
        let model = AutoScanViewModel(detector: nil)
        let camera = CameraViewController()
        var factors: [CGFloat] = []
        var sessionAfterPause: UUID?
        camera.zoomDevice = immediateZoomDevice(maximum: 2.4) { value in
            XCTAssertTrue(model.isActive)
            XCTAssertFalse(model.canCaptureManually)
            if let sessionAfterPause { XCTAssertEqual(model.scanSessionID, sessionAfterPause) }
            sessionAfterPause = model.scanSessionID
            factors.append(value)
        }
        camera.shouldChangeZoom = { _ in model.canChangeZoom }
        camera.willChangeZoom = { value in model.prepareForZoomChange(from: camera.appliedZoom, to: value) }
        camera.onZoomMotionChanged = { model.isZoomMoving = $0 }
        model.start()
        camera.setZoom(3, animated: true)
        try await waitForScanCount { camera.isZoomMoving }
        XCTAssertLessThan(camera.appliedZoom, 2.4)
        model.start()
        XCTAssertTrue(model.isActive)
        try await waitForScanCount { !camera.isZoomMoving }
        XCTAssertEqual(camera.appliedZoom, 2.4)
        XCTAssertTrue(model.canCaptureManually)
        XCTAssertEqual(model.stationStatus, .paused)
        try await completeBaselineLearningAfterZoom(model)
        XCTAssertGreaterThan(factors.count, 2)
        XCTAssertTrue(zip(factors, factors.dropFirst()).allSatisfy { $0 <= $1 })
        model.start()
        XCTAssertEqual(model.stationStatus, .ready)
        XCTAssertFalse(model.isCalibrated)
        model.stop()
    }

    func testRetargetPinchAndNavigationDiscardOldMotion() async throws {
        let camera = CameraViewController()
        camera.zoomDevice = immediateZoomDevice(maximum: 4)
        camera.setZoom(3, animated: true)
        try await waitForScanCount { camera.appliedZoom > 1.1 }
        camera.setZoom(1.5, animated: true)
        try await waitForScanCount { !camera.isZoomMoving }
        XCTAssertEqual(camera.appliedZoom, 1.5)
        camera.setZoom(3.5, animated: true)
        try await waitForScanCount { camera.appliedZoom > 1.6 }
        let start = camera.appliedZoom
        camera.beginPinch()
        camera.applyPinch(scale: 1.1)
        camera.endPinch()
        XCTAssertEqual(camera.appliedZoom, start * 1.1, accuracy: 0.001)
        camera.setZoom(3, animated: true)
        try await waitForScanCount { camera.isZoomMoving }
        camera.cancelZoom()
        let stopped = camera.appliedZoom
        // Wait beyond the old destination: a stale task would overwrite the pinch/navigation result.
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(camera.appliedZoom, stopped)
        XCTAssertFalse(camera.isZoomMoving)
    }

    private func retryFailedZoom(
        _ coordinator: CameraCaptureCoordinator, camera: CameraViewController, detection: CardDetectionViewModel
    ) async throws {
        XCTAssertNotNil(coordinator.zoomFailure)
        camera.zoomDevice = immediateZoomDevice(maximum: 2.4)
        coordinator.retryZoom()
        try await waitForScanCount { !camera.isZoomMoving && detection.zoomFactor == 2 }
        XCTAssertNil(coordinator.zoomFailure)
    }

    func testLateHardwareCompletionCannotPublishAfterNavigation() throws {
        let camera = CameraViewController()
        var authorize: CameraZoomDevice.Authorization?
        var complete: CameraZoomDevice.Completion?
        camera.zoomDevice = CameraZoomDevice(maximum: 4, change: { _, permission, callback in
            authorize = permission
            complete = callback
        })
        camera.setZoom(3, animated: true)
        XCTAssertTrue(try XCTUnwrap(authorize)())
        XCTAssertTrue(camera.isZoomMoving)
        camera.cancelZoom()
        try XCTUnwrap(complete)(true)
        XCTAssertEqual(camera.appliedZoom, 1)
        XCTAssertFalse(camera.isZoomMoving)
        XCTAssertFalse(try XCTUnwrap(authorize)())
    }

    func testStopCancelsQueuedZoomFrames() {
        let model = AutoScanViewModel(detector: nil)
        let camera = CameraViewController()
        let coordinator = CameraCaptureCoordinator()
        coordinator.controller = camera
        model.captureCoordinator = coordinator
        camera.zoomDevice = immediateZoomDevice(maximum: 4)
        camera.shouldChangeZoom = { _ in model.canChangeZoom }
        camera.willChangeZoom = { model.prepareForZoomChange(from: camera.appliedZoom, to: $0) }
        camera.onZoomMotionChanged = { model.isZoomMoving = $0 }
        var frames: [@MainActor @Sendable () -> Void] = []
        camera.scheduleZoomFrame = { frames.append($0) }
        model.start()
        camera.setZoom(3, animated: true)
        let pausedAt = camera.appliedZoom
        XCTAssertTrue(camera.isZoomMoving)
        model.stop()
        XCTAssertFalse(camera.isZoomMoving)
        frames.forEach { $0() }
        XCTAssertEqual(camera.appliedZoom, pausedAt)
    }

    func testSmallActualMovementSuspendsRatherThanStoppingStation() async throws {
        let camera = CameraViewController()
        let model = AutoScanViewModel(detector: nil)
        camera.zoomDevice = immediateZoomDevice(maximum: 4) { _ in
            XCTAssertTrue(model.isActive)
            XCTAssertTrue(model.isZoomMoving)
        }
        camera.onZoomMotionChanged = { model.isZoomMoving = $0 }
        camera.willChangeZoom = { model.prepareForZoomChange(from: camera.appliedZoom, to: $0) }
        model.start()
        camera.setZoom(1.00001)
        XCTAssertEqual(camera.appliedZoom, 1.00001)
        XCTAssertEqual(model.stationStatus, .paused)
        try await completeBaselineLearningAfterZoom(model)
        model.stop()
    }

    func testNoOpAndConfigurationFailurePreserveStationAndReleaseMotion() async throws {
        let camera = CameraViewController()
        let model = AutoScanViewModel(detector: nil)
        camera.zoomDevice = immediateZoomDevice(maximum: 1)
        camera.willChangeZoom = { model.prepareForZoomChange(from: camera.appliedZoom, to: $0) }
        camera.onZoomMotionChanged = { model.isZoomMoving = $0 }
        model.start()
        camera.setZoom(3, animated: true)
        XCTAssertTrue(model.isActive)
        XCTAssertFalse(camera.isZoomMoving)
        var failed = false
        camera.onZoomFailure = { _ in failed = true }
        camera.zoomDevice = immediateZoomDevice(maximum: 4, accepts: false)
        camera.setZoom(2, animated: true)
        try await waitForScanCount { failed }
        XCTAssertTrue(model.isActive)
        XCTAssertFalse(camera.isZoomMoving)
        XCTAssertEqual(camera.appliedZoom, 1)
        model.stop()
    }

    func testHostedTableShutterKeepsZoomLockedThroughCropAndNavigation() async throws {
        let app = AppModel()
        app.onDeviceCropEnabled = true
        let context = try makeScanCountContext()
        let gate = TableCropGate()
        let queue = RecognitionQueue()
        queue.maxConcurrent = 0
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }
        let model = AutoScanViewModel(detectorProvider: { nil }, recognitionQueue: queue,
                                     cropImage: { _, _ in await gate.run() })
        model.captureFocusedPhoto = { _ in .success(.cameraCapture(image: image, data: Data([1]))) }
        let camera = CameraViewController()
        var applied: [CGFloat] = []
        camera.zoomDevice = immediateZoomDevice(maximum: 5) { applied.append($0) }
        let state = CaptureHostState()
        let view = CaptureZoomHost(state: state, mode: .scan, model: model, detection: CardDetectionViewModel(),
                                   coordinator: CameraCaptureCoordinator(), camera: camera)
            .environment(app).modelContainer(context.container)
        let window = makeScanCountWindow(view: view)
        defer { closeScanCountWindow(window) }
        try await waitForScanCount { model.appModel != nil }
        try view.inspect().find(CaptureButton.self).actualView().action()
        try await gate.waitUntilStarted()
        camera.setZoom(2)
        camera.applyPinch(scale: 1.5)
        XCTAssertTrue(applied.isEmpty)
        XCTAssertFalse(model.canCaptureManually)
        state.active = false
        await gate.finish(image)
        try await waitForScanCount { model.canCaptureManually }
        XCTAssertEqual(queue.pendingCount, 1)
    }

    func testEveryZoomPathRejectsChangesDuringAcceptedCapture() async throws {
        let model = AutoScanViewModel(detector: nil)
        let gate = ZoomPhotoGate()
        model.captureFocusedPhoto = { _ in await gate.run() }
        let camera = CameraViewController()
        var applied: [CGFloat] = []
        camera.zoomDevice = immediateZoomDevice(maximum: 5) { applied.append($0) }
        camera.shouldChangeZoom = { _ in model.canCaptureManually }
        model.start()
        model.captureManually()
        try await waitForScanCount { gate.waiting }
        camera.setZoom(2)
        camera.applyPinch(scale: 1.5)
        XCTAssertEqual(camera.appliedZoom, 1)
        XCTAssertTrue(applied.isEmpty)
        gate.finish()
        try await waitForScanCount { model.canCaptureManually }
        camera.setZoom(2)
        XCTAssertEqual(applied, [2])
        model.stop()
    }
}

@MainActor
final class CapturePresentationWiringTests: XCTestCase {
    func testReturningToCaptureRestoresItsSavedActualZoom() async throws {
        let app = AppModel()
        let context = try makeScanCountContext()
        let model = AutoScanViewModel(detector: nil)
        let detection = CardDetectionViewModel()
        let coordinator = CameraCaptureCoordinator()
        let camera = CameraViewController()
        camera.zoomDevice = immediateZoomDevice(maximum: 4)
        let state = CaptureHostState()
        let view = CaptureZoomHost(state: state, mode: .scan, model: model, detection: detection,
                                   coordinator: coordinator, camera: camera)
            .environment(app).modelContainer(context.container)
        let window = makeScanCountWindow(view: view)
        defer { closeScanCountWindow(window) }
        try await waitForScanCount { coordinator.controller != nil && model.appModel != nil }
        camera.setZoom(1.5)
        model.start()
        state.active = false
        try await waitForScanCount { !model.isActive }
        camera.setZoom(2) // The other mode changes the shared physical camera.
        state.active = true
        try await waitForScanCount { camera.appliedZoom == 1.5 && detection.zoomFactor == 1.5 }
        let control = try view.inspect().find(ZoomPresetControl.self).actualView()
        control.onSelect(1)
        try await waitForScanCount { !camera.isZoomMoving && detection.zoomFactor == 1 }
        XCTAssertEqual(camera.appliedZoom, 1)
    }

    func testBothCaptureModesWireTheCloseFocusPolicyAndItsWideFallback() async throws {
        for mode in DetectionMode.allCases {
            let app = AppModel()
            let context = try makeScanCountContext()
            let model = AutoScanViewModel(detector: nil)
            let camera = CameraViewController()
            let coordinator = CameraCaptureCoordinator()
            let view = CaptureZoomHost(state: CaptureHostState(), mode: mode, model: model,
                                       detection: CardDetectionViewModel(), coordinator: coordinator, camera: camera)
                .environment(app).modelContainer(context.container)
            let window = makeScanCountWindow(view: view)
            defer { closeScanCountWindow(window) }
            try await waitForScanCount { coordinator.controller != nil }
            XCTAssertEqual(camera.camera.preferredDeviceType(closeUpAvailable: true), .builtInUltraWideCamera)
            XCTAssertEqual(camera.camera.preferredDeviceType(closeUpAvailable: false), .builtInWideAngleCamera)
        }
    }

    func testPresetReadoutMovesToTheChosenAnchorWithoutCountingAppliedFrames() async throws {
        let app = AppModel()
        let context = try makeScanCountContext()
        let model = AutoScanViewModel(detector: nil)
        let detection = CardDetectionViewModel()
        let coordinator = CameraCaptureCoordinator()
        let camera = CameraViewController()
        camera.zoomDevice = immediateZoomDevice(maximum: 4)
        camera.scheduleZoomFrame = { _ in }
        let view = CaptureZoomHost(state: CaptureHostState(), mode: .scan, model: model, detection: detection,
                                   coordinator: coordinator, camera: camera)
            .environment(app).modelContainer(context.container)
        let window = makeScanCountWindow(view: view)
        defer { closeScanCountWindow(window) }
        try await waitForScanCount { coordinator.controller != nil && model.appModel != nil }
        coordinator.setZoom(2)
        XCTAssertGreaterThan(camera.appliedZoom, 1)
        XCTAssertLessThan(camera.appliedZoom, 2)
        let selected = try view.inspect().find(ZoomPresetControl.self).actualView()
        XCTAssertEqual(selected.currentZoom, 2)
        camera.beginPinch()
        camera.applyPinch(scale: 1.1)
        camera.endPinch()
        let pinched = try view.inspect().find(ZoomPresetControl.self).actualView()
        XCTAssertEqual(pinched.currentZoom, camera.appliedZoom)
    }

    func testDelayedZoomFrameCatchesUpToElapsedTimeInsteadOfExtendingTheRamp() async throws {
        let camera = CameraViewController()
        camera.zoomDevice = immediateZoomDevice(maximum: 4)
        var resumed = false
        camera.scheduleZoomFrame = { frame in
            guard !resumed else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                frame()
                resumed = true
            }
        }
        camera.setZoom(3, animated: true)
        try await waitForScanCount { resumed }
        XCTAssertEqual(camera.appliedZoom, 3)
        XCTAssertFalse(camera.isZoomMoving)
    }

}

@MainActor
@Observable
private final class CaptureHostState { var active = true }

private struct CaptureZoomHost: View {
    let state: CaptureHostState
    let mode: DetectionMode
    let model: AutoScanViewModel
    let detection: CardDetectionViewModel
    let coordinator: CameraCaptureCoordinator
    let camera: CameraViewController

    var body: some View {
        ScanView(detectionMode: .constant(mode), isActive: state.active,
                 autoScanViewModel: model, detectionViewModel: detection, captureCoordinator: coordinator,
                 previewContent: { preview in
                     AnyView(Color.black.onAppear { preview.connect(camera) })
                 })
    }
}

@MainActor
private final class ZoomPhotoGate {
    private var continuation: CheckedContinuation<CameraCaptureResult, Never>?
    var waiting: Bool { continuation != nil }
    func run() async -> CameraCaptureResult { await withCheckedContinuation { continuation = $0 } }
    func finish() { continuation?.resume(returning: .failure(.unavailable)); continuation = nil }
}

private actor TableCropGate {
    private var continuation: CheckedContinuation<CardCropResult, Never>?
    func run() async -> CardCropResult { await withCheckedContinuation { continuation = $0 } }
    func finish(_ image: UIImage) {
        continuation?.resume(returning: CardCropResult(crops: [image], detectedCount: 1))
        continuation = nil
    }
    func waitUntilStarted() async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while continuation == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(continuation)
    }
}

@MainActor
func immediateZoomDevice(
    maximum: CGFloat, accepts: Bool = true, didApply: @escaping (CGFloat) -> Void = { _ in }
) -> CameraZoomDevice {
    CameraZoomDevice(maximum: maximum, change: { value, authorize, complete in
        guard accepts else { complete(false); return }
        guard authorize() else { return }
        didApply(value)
        complete(true)
    })
}
