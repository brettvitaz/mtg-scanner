import AVFoundation
import SwiftUI

/// Observable state for the real-time card detection feature.
@MainActor
@Observable
final class CardDetectionViewModel {

    var detectedCardCount: Int = 0
    var cameraPermissionDenied = false
    var cameraPermissionGranted = false
    var zoomFactor: CGFloat = 1.0
    var torchLevel: Float = 0

    func handleDetectedCards(_ cards: [DetectedCard]) {
        detectedCardCount = cards.count
    }

    func updateCameraPermission(granted: Bool) {
        cameraPermissionDenied = !granted
        cameraPermissionGranted = granted
    }

    func requestCameraPermissionIfNeeded() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    self?.updateCameraPermission(granted: granted)
                }
            }
        case .denied, .restricted:
            updateCameraPermission(granted: false)
        case .authorized:
            updateCameraPermission(granted: true)
        @unknown default:
            break
        }
    }
}
