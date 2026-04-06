import AVFoundation
import SwiftUI

/// Observable state for the real-time card detection feature.
@MainActor
@Observable
final class CardDetectionViewModel {

    var detectedCardCount: Int = 0
    var cameraPermissionDenied = false
    var zoomFactor: CGFloat = 1.0
    var torchLevel: Float = 0

    func handleDetectedCards(_ cards: [DetectedCard]) {
        detectedCardCount = cards.count
    }

    func requestCameraPermissionIfNeeded() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    self?.cameraPermissionDenied = !granted
                }
            }
        case .denied, .restricted:
            cameraPermissionDenied = true
        case .authorized:
            break
        @unknown default:
            break
        }
    }
}
