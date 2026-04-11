import SwiftUI

/// Bridges ``FixtureCameraViewController`` into SwiftUI for preview/simulator builds.
///
/// Mirrors the public API of ``CameraPreviewRepresentable`` for the parts that
/// ``PreviewGalleryRootView`` needs for the `scan` route.
struct FixtureCameraPreviewRepresentable: UIViewControllerRepresentable {

    var onDetectedCardsChanged: (([DetectedCard]) -> Void)?

    func makeUIViewController(context: Context) -> FixtureCameraViewController {
        let vc = FixtureCameraViewController()
        vc.onDetectedCardsChanged = onDetectedCardsChanged
        return vc
    }

    func updateUIViewController(_ vc: FixtureCameraViewController, context: Context) {
        vc.onDetectedCardsChanged = onDetectedCardsChanged
    }
}
