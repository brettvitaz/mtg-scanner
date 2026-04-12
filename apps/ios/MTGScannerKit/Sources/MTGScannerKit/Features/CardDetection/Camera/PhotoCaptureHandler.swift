import AVFoundation
import UIKit

/// Owns the completion and AVCapturePhotoCaptureDelegate for exactly one photo capture.
///
/// By making each capture its own delegate, a stale AVFoundation callback can never
/// reach a different capture's completion — it only talks to the object it was given.
///
/// Both `cancel()` and `photoOutput(_:didFinishProcessingPhoto:)` are serialized through
/// `sessionQueue` so the `completion` slot has a single writer at a time.
final class PhotoCaptureHandler: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {

    let generation: Int
    private let maxPhotoDimensions: CMVideoDimensions
    private var completion: (@Sendable (RecognitionImagePayload?) -> Void)?
    private let sessionQueue: DispatchQueue
    private let onDone: @Sendable (PhotoCaptureHandler) -> Void

    init(
        generation: Int,
        maxPhotoDimensions: CMVideoDimensions,
        completion: @escaping @Sendable (RecognitionImagePayload?) -> Void,
        sessionQueue: DispatchQueue,
        onDone: @escaping @Sendable (PhotoCaptureHandler) -> Void
    ) {
        self.generation = generation
        self.maxPhotoDimensions = maxPhotoDimensions
        self.completion = completion
        self.sessionQueue = sessionQueue
        self.onDone = onDone
    }

    func issueCapture(to output: AVCapturePhotoOutput) {
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        if maxPhotoDimensions.width > 0 {
            settings.maxPhotoDimensions = maxPhotoDimensions
        }
        let supportsQuality = output.maxPhotoQualityPrioritization.rawValue >=
            AVCapturePhotoOutput.QualityPrioritization.quality.rawValue
        if supportsQuality {
            settings.photoQualityPrioritization = .quality
        }
        output.capturePhoto(with: settings, delegate: self)
    }

    /// Called by `stop()` (on sessionQueue) to resolve the pending continuation with nil.
    func cancel() {
        let pending = completion
        completion = nil
        DispatchQueue.main.async { pending?(nil) }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        // Serialize completion mutation onto sessionQueue so cancel() and this delegate
        // callback cannot race — only one of them will find a non-nil completion.
        let payload: RecognitionImagePayload?
        if error == nil,
           let photoData = photo.fileDataRepresentation(),
           let image = UIImage(data: photoData) {
            payload = .cameraCapture(image: image, data: photoData)
        } else {
            payload = nil
        }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let pending = self.completion
            self.completion = nil
            self.onDone(self)
            guard let pending else { return }
            DispatchQueue.main.async { pending(payload) }
        }
    }
}
