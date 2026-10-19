import AVFoundation
import OSLog

/// Hardware zoom transactions stay on the shared session queue.
struct CameraZoomDevice: Sendable {
    typealias Authorization = @MainActor @Sendable () -> Bool
    typealias Completion = @MainActor (Bool) -> Void
    typealias Progress = @MainActor (CGFloat) -> Void
    typealias Ramp = @MainActor (CGFloat, @escaping Authorization, @escaping Progress, @escaping Completion) -> Void
    let maximum: CGFloat
    let currentFactor: (@MainActor () -> CGFloat)?
    let ramp: Ramp?
    let cancel: (@MainActor (@escaping Progress) -> Void)?
    let change: @MainActor (CGFloat, @escaping Authorization, @escaping Completion) -> Void

    init(maximum: CGFloat, currentFactor: (@MainActor () -> CGFloat)? = nil, ramp: Ramp? = nil,
         cancel: (@MainActor (@escaping Progress) -> Void)? = nil,
         change: @escaping @MainActor (CGFloat, @escaping Authorization, @escaping Completion) -> Void) {
        self.maximum = maximum
        self.currentFactor = currentFactor
        self.ramp = ramp
        self.cancel = cancel
        self.change = change
    }

    static func rampRate(from current: CGFloat, to destination: CGFloat) -> Float {
        Float(abs(log2(destination / current)) / 0.25)
    }

    init?(_ manager: CameraSessionManager, owner: UUID) {
        guard let device = manager.captureDevice else { return nil }
        maximum = device.activeFormat.videoMaxZoomFactor
        currentFactor = { device.videoZoomFactor }
        change = { factor, authorize, complete in
            manager.changeZoom(factor, owner: owner, authorize: authorize, complete: complete)
        }
        ramp = { factor, authorize, progress, complete in
            manager.rampZoom(factor, owner: owner, authorize: authorize, progress: progress, complete: complete)
        }
        cancel = { progress in manager.cancelZoomRamp(owner: owner, progress: progress) }
    }
}

extension CameraSessionManager {
    func changeZoom(_ factor: CGFloat, owner: UUID, authorize: @escaping CameraZoomDevice.Authorization,
                    complete: @escaping CameraZoomDevice.Completion) {
        sessionQueue.async { [self] in
            guard ownsCamera(owner), let device = captureDevice else {
                Task { @MainActor in complete(false) }
                return
            }
            do {
                try device.lockForConfiguration()
                let allowed = DispatchQueue.main.sync { MainActor.assumeIsolated { authorize() } }
                if allowed {
                    zoomRampGeneration &+= 1
                    device.videoZoomFactor = factor
                }
                device.unlockForConfiguration()
                Task { @MainActor in complete(allowed) }
            } catch { reportZoomFailure(error, complete: complete) }
        }
    }

    func rampZoom(_ factor: CGFloat, owner: UUID, authorize: @escaping CameraZoomDevice.Authorization,
                  progress: @escaping CameraZoomDevice.Progress, complete: @escaping CameraZoomDevice.Completion) {
        sessionQueue.async { [self] in
            guard ownsCamera(owner), let device = captureDevice else {
                Task { @MainActor in complete(false) }
                return
            }
            do {
                try device.lockForConfiguration()
                let allowed = DispatchQueue.main.sync { MainActor.assumeIsolated { authorize() } }
                if allowed {
                    zoomRampGeneration &+= 1
                    let rate = CameraZoomDevice.rampRate(from: device.videoZoomFactor, to: factor)
                    device.ramp(toVideoZoomFactor: factor, withRate: rate)
                }
                device.unlockForConfiguration()
                if allowed {
                    pollZoomRamp(generation: zoomRampGeneration, progress: progress, complete: complete)
                } else {
                    Task { @MainActor in complete(false) }
                }
            } catch { reportZoomFailure(error, complete: complete) }
        }
    }

    private func pollZoomRamp(generation: Int, progress: @escaping CameraZoomDevice.Progress,
                              complete: @escaping CameraZoomDevice.Completion) {
        sessionQueue.asyncAfter(deadline: .now() + 0.016) { [self] in
            guard generation == zoomRampGeneration, let device = captureDevice else { return }
            let factor = device.videoZoomFactor
            let moving = device.isRampingVideoZoom
            Task { @MainActor in
                progress(factor)
                if !moving { complete(true) }
            }
            if moving { pollZoomRamp(generation: generation, progress: progress, complete: complete) }
        }
    }

    func cancelZoomRamp(owner: UUID, progress: @escaping CameraZoomDevice.Progress) {
        sessionQueue.async { [self] in
            guard ownsCamera(owner), let device = captureDevice else { return }
            do {
                try device.lockForConfiguration()
                zoomRampGeneration &+= 1
                // Assigning the instantaneous factor stops the ramp without a deceleration tail.
                // This keeps manual capture and direct pinch from racing residual optical motion.
                let factor = device.videoZoomFactor
                device.videoZoomFactor = factor
                device.unlockForConfiguration()
                Task { @MainActor in progress(factor) }
            } catch {
                Logger(subsystem: "com.mtgscanner", category: "CameraZoom")
                    .error("Zoom cancellation failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func reportZoomFailure(_ error: Error, complete: @escaping CameraZoomDevice.Completion) {
        Logger(subsystem: "com.mtgscanner", category: "CameraZoom")
            .error("Zoom configuration failed: \(error.localizedDescription, privacy: .public)")
        Task { @MainActor in complete(false) }
    }
}
