import SwiftUI
import UIKit
import ViewInspector
import XCTest
@testable import MTGScannerKit

@MainActor
final class CaptureZoomWiringTests: XCTestCase {
    func testHostedSharedPresetControlsReportDeviceClampAndPinchInBothModes() async throws {
        for mode in DetectionMode.allCases {
            let app = AppModel()
            let context = try makeScanCountContext()
            app.modelContext = context
            let model = AutoScanViewModel(detector: nil)
            let detection = CardDetectionViewModel()
            let coordinator = CameraCaptureCoordinator()
            let camera = CameraViewController()
            var applied: [CGFloat] = []
            camera.zoomDevice = CameraZoomDevice(maximum: 2.4) { applied.append($0); return true }
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
                XCTAssertEqual(detection.zoomFactor, expected, accuracy: 0.001)
            }
            XCTAssertEqual(applied, [1.5, 2, 2.4, 1])
            camera.applyPinch(scale: 1.73)
            XCTAssertEqual(detection.zoomFactor, 1.73, accuracy: 0.001)
            let refreshed = try view.inspect().find(ZoomPresetControl.self).actualView()
            XCTAssertEqual(ZoomPresetControl.label(refreshed.currentZoom), "1.7×")
            model.start()
            camera.zoomDevice = CameraZoomDevice(maximum: 2.4) { _ in false }
            camera.setZoom(2)
            XCTAssertTrue(model.isActive)
            XCTAssertEqual(detection.zoomFactor, 1.73, accuracy: 0.001)
            state.active = false
            try await waitForScanCount { !model.isActive && detection.zoomFactor == 1 }
            XCTAssertFalse(model.isCalibrated)
        }
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
        camera.zoomDevice = CameraZoomDevice(maximum: 5) { applied.append($0); return true }
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
        camera.zoomDevice = CameraZoomDevice(maximum: 5) { applied.append($0); return true }
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
