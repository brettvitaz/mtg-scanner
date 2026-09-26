#if DEBUG
import Foundation
import Photos

protocol RawCaptureSaving: Sendable {
    func saveRawCapture(_ payload: RecognitionImagePayload) async
}

struct RawCaptureDebugSaver: RawCaptureSaving {
    func saveRawCapture(_ payload: RecognitionImagePayload) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            print("Raw capture debug save skipped: Photos add-only access denied.")
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: payload.uploadData, options: nil)
            }
        } catch {
            print("Raw capture debug save failed: \(error.localizedDescription)")
        }
    }
}
#endif
