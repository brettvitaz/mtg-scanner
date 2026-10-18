import AVFoundation
import OSLog

/// An authorized configuration transaction: lock failures occur before Station is paused.
struct CameraZoomDevice: Sendable {
    typealias Authorization = @MainActor @Sendable () -> Bool
    typealias Completion = @MainActor (Bool) -> Void
    let maximum: CGFloat
    let change: @MainActor (CGFloat, @escaping Authorization, @escaping Completion) -> Void

    init(maximum: CGFloat,
         change: @escaping @MainActor (CGFloat, @escaping Authorization, @escaping Completion) -> Void) {
        self.maximum = maximum
        self.change = change
    }

    init?(_ manager: CameraSessionManager) {
        guard let device = manager.captureDevice else { return nil }
        maximum = device.activeFormat.videoMaxZoomFactor
        change = { factor, authorize, complete in
            manager.changeZoom(factor, authorize: authorize, complete: complete)
        }
    }
}

extension CameraSessionManager {
    func changeZoom(
        _ factor: CGFloat, authorize: @escaping CameraZoomDevice.Authorization,
        complete: @escaping CameraZoomDevice.Completion
    ) {
        sessionQueue.async { [self] in
            guard let device = captureDevice else {
                Task { @MainActor in complete(false) }
                return
            }
            do {
                try device.lockForConfiguration()
            } catch {
                Logger(subsystem: "com.mtgscanner", category: "CameraZoom")
                    .error("Zoom configuration failed: \(error.localizedDescription, privacy: .public)")
                Task { @MainActor in complete(false) }
                return
            }
            // MainActor never waits on this queue. Recheck generation and the accepted-photo
            // guard under the configuration lock, immediately before changing the camera.
            let allowed = DispatchQueue.main.sync { MainActor.assumeIsolated { authorize() } }
            if allowed { device.videoZoomFactor = factor }
            device.unlockForConfiguration()
            Task { @MainActor in complete(allowed) }
        }
    }
}
