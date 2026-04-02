import AVFoundation
import SwiftUI

/// Observable state for the real-time card detection feature.
@MainActor
final class CardDetectionViewModel: ObservableObject {

    @Published var detectionMode: DetectionMode = .table
    @Published var detectedCardCount: Int = 0
    @Published var cameraPermissionDenied = false
    @Published var zoomFactor: CGFloat = 1.0
    @Published var torchLevel: Float = 0

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
