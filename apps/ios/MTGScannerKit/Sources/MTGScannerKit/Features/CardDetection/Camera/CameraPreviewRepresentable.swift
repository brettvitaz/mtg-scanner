import AVFoundation
import SwiftUI

/// Bridges `CameraViewController` into SwiftUI.
///
/// Passes `detectionMode` updates down to the controller, forwards
/// detected card changes back up, and wires the capture coordinator.
struct CameraPreviewRepresentable: UIViewControllerRepresentable {

    @Binding var detectionMode: DetectionMode
    var camera: AutoScanCamera = .standard
    var onDetectedCardsChanged: (([DetectedCard]) -> Void)?
    var captureCoordinator: CameraCaptureCoordinator?
    var onZoomFactorChanged: ((CGFloat) -> Void)?
    var willChangeZoom: ((CGFloat) -> Bool)?
    var onZoomMotionChanged: ((Bool) -> Void)?
    var onZoomFailure: ((CGFloat) -> Void)?
    var shouldChangeZoom: ((CGFloat) -> Bool)?
    /// Receives raw `CMSampleBuffer` frames on the session queue when in Auto Scan mode.
    var onAutoScanFrame: ((CMSampleBuffer) -> Void)?
    /// Torch brightness: 0 = off, 0.1–1.0 = on at that brightness.
    var torchLevel: Float = 0
    /// Exposure bias in EV stops. Positive = brighter, negative = darker.
    var exposureBias: Float = 0

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        connect(vc)
        return vc
    }

    static func dismantleUIViewController(_ vc: CameraViewController, coordinator: ()) {
        vc.shutDown()
    }

    func updateUIViewController(_ vc: CameraViewController, context: Context) {
        connect(vc)
        vc.updateDetectionMode(detectionMode)
        vc.setTorchLevel(torchLevel)
        vc.setExposureBias(exposureBias)
        captureCoordinator?.controller = vc
    }
    func connect(_ vc: CameraViewController) {
        vc.camera = camera
        vc.onDetectedCardsChanged = onDetectedCardsChanged
        vc.onZoomFactorChanged = onZoomFactorChanged
        vc.shouldChangeZoom = shouldChangeZoom
        vc.willChangeZoom = willChangeZoom
        vc.onZoomMotionChanged = onZoomMotionChanged
        vc.onZoomFailure = onZoomFailure
        vc.onAutoScanFrame = onAutoScanFrame
        captureCoordinator?.controller = vc
    }

}
