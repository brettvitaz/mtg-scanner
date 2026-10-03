import UIKit

/// Bridges SwiftUI's async/await world to CameraViewController's callback-based capture.
@MainActor
@Observable
final class CameraCaptureCoordinator {
    weak var controller: CameraViewController?

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
