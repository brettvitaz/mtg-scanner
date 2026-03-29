import SwiftUI

/// Bridges `CameraViewController` into SwiftUI.
///
/// Passes `detectionMode` updates down to the controller, forwards
/// detected card changes back up, and wires the capture coordinator.
struct CameraPreviewRepresentable: UIViewControllerRepresentable {

    @Binding var detectionMode: DetectionMode
    var zoomFactor: CGFloat = 1.0
    var onDetectedCardsChanged: (([DetectedCard]) -> Void)?
    var captureCoordinator: CameraCaptureCoordinator?
    var onZoomFactorChanged: ((CGFloat) -> Void)?

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.onDetectedCardsChanged = onDetectedCardsChanged
        vc.onZoomFactorChanged = onZoomFactorChanged
        captureCoordinator?.controller = vc
        return vc
    }

    func updateUIViewController(_ vc: CameraViewController, context: Context) {
        vc.updateDetectionMode(detectionMode)
        vc.onDetectedCardsChanged = onDetectedCardsChanged
        vc.onZoomFactorChanged = onZoomFactorChanged
        vc.setZoom(zoomFactor)
        captureCoordinator?.controller = vc
    }
}
