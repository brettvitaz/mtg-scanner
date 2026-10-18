import AVFoundation
import SwiftUI

/// Bridges `CameraViewController` into SwiftUI.
///
/// Passes `detectionMode` updates down to the controller, forwards
/// detected card changes back up, and wires the capture coordinator.
struct CameraPreviewRepresentable: UIViewControllerRepresentable {

    @Binding var detectionMode: DetectionMode
    var zoomFactor: CGFloat = 1.0
    var camera: AutoScanCamera = .standard
    var onDetectedCardsChanged: (([DetectedCard]) -> Void)?
    var captureCoordinator: CameraCaptureCoordinator?
    var onZoomFactorChanged: ((CGFloat) -> Void)?
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
        vc.setZoom(zoomFactor)
        vc.setTorchLevel(torchLevel)
        vc.setExposureBias(exposureBias)
        captureCoordinator?.controller = vc
    }
    func connect(_ vc: CameraViewController) {
        vc.camera = camera
        vc.onDetectedCardsChanged = onDetectedCardsChanged
        vc.onZoomFactorChanged = onZoomFactorChanged
        vc.shouldChangeZoom = shouldChangeZoom
        vc.onAutoScanFrame = onAutoScanFrame
        captureCoordinator?.controller = vc
    }

}
