import UIKit

/// Bridges SwiftUI's async/await world to CameraViewController's callback-based capture.
@MainActor
@Observable
final class CameraCaptureCoordinator {
    weak var controller: CameraViewController?

    func capturePhoto() async -> RecognitionImagePayload? {
        guard let controller else { return nil }
        return await withCheckedContinuation { continuation in
            controller.capturePhoto { payload in
                continuation.resume(returning: payload)
            }
        }
    }
}
