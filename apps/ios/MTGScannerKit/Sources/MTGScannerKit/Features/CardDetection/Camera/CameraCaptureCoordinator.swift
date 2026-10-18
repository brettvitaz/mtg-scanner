import UIKit

/// Bridges SwiftUI's async/await world to CameraViewController's callback-based capture.
@MainActor
@Observable
final class CameraCaptureCoordinator {
    weak var controller: CameraViewController?

    var zoomFailure: String?
    private var requestedZoom: CGFloat = 1

    func setZoom(_ factor: CGFloat) {
        requestedZoom = factor
        zoomFailure = nil
        guard let controller else { reportZoomFailure(factor); return }
        controller.setZoom(factor, animated: true)
    }

    func reportZoomFailure(_ factor: CGFloat) {
        requestedZoom = factor
        zoomFailure = "Zoom failed. Retry"
    }

    func retryZoom() { setZoom(requestedZoom) }
    func cancelZoom() { controller?.cancelZoom() }

    func focus(on point: CGPoint) {
        controller?.focus(on: point)
    }

    func captureFocusedPhoto(focusPoint: CGPoint?) async -> CameraCaptureResult {
        guard let controller else { return .failure(.unavailable) }
        return await withCheckedContinuation { continuation in
            controller.captureFocusedPhoto(focusPoint: focusPoint) { result in
                continuation.resume(returning: result)
            }
        }
    }
}
