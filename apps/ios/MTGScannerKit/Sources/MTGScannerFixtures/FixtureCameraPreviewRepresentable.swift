import MTGScannerKit
import SwiftUI

/// Bridges ``FixtureCameraViewController`` into SwiftUI for preview/simulator builds.
///
/// Mirrors the public API of ``CameraPreviewRepresentable`` for the parts that
/// ``PreviewGalleryRootView`` needs for the `scan` route.
public struct FixtureCameraPreviewRepresentable: UIViewControllerRepresentable {

    public var onDetectedCardsChanged: (([DetectedCard]) -> Void)?

    public init(onDetectedCardsChanged: (([DetectedCard]) -> Void)? = nil) {
        self.onDetectedCardsChanged = onDetectedCardsChanged
    }

    public func makeUIViewController(context: Context) -> FixtureCameraViewController {
        let vc = FixtureCameraViewController()
        vc.onDetectedCardsChanged = onDetectedCardsChanged
        return vc
    }

    public func updateUIViewController(_ vc: FixtureCameraViewController, context: Context) {
        vc.onDetectedCardsChanged = onDetectedCardsChanged
    }
}
