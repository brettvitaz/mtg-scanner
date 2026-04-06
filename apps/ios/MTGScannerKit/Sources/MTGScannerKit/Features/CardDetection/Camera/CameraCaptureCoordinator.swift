import UIKit

/// Bridges SwiftUI's async/await world to CameraViewController's callback-based capture.
@MainActor
final class CameraCaptureCoordinator: ObservableObject {
    weak var controller: CameraViewController?

    func capturePhoto() async -> UIImage? {
        guard let controller else { return nil }
        return await withCheckedContinuation { continuation in
            controller.capturePhoto { image in
                continuation.resume(returning: image)
            }
        }
    }
}
