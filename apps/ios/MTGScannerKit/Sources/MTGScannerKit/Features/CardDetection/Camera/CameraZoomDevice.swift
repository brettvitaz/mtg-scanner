import AVFoundation
import OSLog

/// The hardware boundary for both pinch and menu zoom requests.
struct CameraZoomDevice {
    private static let logger = Logger(subsystem: "com.mtgscanner", category: "CameraZoom")
    let maximum: CGFloat
    let apply: (CGFloat) -> Bool

    init(maximum: CGFloat, apply: @escaping (CGFloat) -> Bool) {
        self.maximum = maximum
        self.apply = apply
    }

    init(_ device: AVCaptureDevice) {
        maximum = device.activeFormat.videoMaxZoomFactor
        apply = { factor in
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = factor
                device.unlockForConfiguration()
                return true
            } catch {
                Self.logger.error("Could not apply zoom: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
    }
}
