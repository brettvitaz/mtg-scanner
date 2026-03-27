import SwiftUI

/// Bridges `CameraViewController` into SwiftUI.
///
/// Passes `detectionMode` updates down to the controller and forwards
/// detected card changes back up through `onDetectedCardsChanged`.
struct CameraPreviewRepresentable: UIViewControllerRepresentable {

    @Binding var detectionMode: DetectionMode
    var onDetectedCardsChanged: (([DetectedCard]) -> Void)?

    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.onDetectedCardsChanged = onDetectedCardsChanged
        return vc
    }

    func updateUIViewController(_ vc: CameraViewController, context: Context) {
        vc.updateDetectionMode(detectionMode)
    }
}
