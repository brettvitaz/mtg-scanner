import AVFoundation
import OSLog
import UIKit

/// Manages the `AVCaptureSession` lifecycle for real-time card detection.
///
/// Responsibilities:
/// - Configure the best available back camera for 1080p video output.
/// - Deliver `CMSampleBuffer` frames to `onFrame` on the session queue.
/// - Start and stop the session from outside the session queue safely.
/// Conforms to ``CameraFrameSource`` alongside the simulator-only ``FixtureFrameSource``.
final class CameraSessionManager: NSObject, CameraFrameSource, @unchecked Sendable {

    // MARK: - Public

    let session = AVCaptureSession()

    /// Called on the session queue for each delivered video frame.
    var onFrame: ((CMSampleBuffer) -> Void)?

    /// Called on the session queue for each delivered pixel buffer (CameraFrameSource).
    var onPixelBuffer: ((CVPixelBuffer, CMTime) -> Void)?

    /// Prefer the physical wide-angle sensor directly over virtual multi-lens devices.
    ///
    /// Virtual devices (triple, dual-wide, dual) switch between physical lenses automatically
    /// as zoom changes. Each switch interrupts the video stream, corrupting the motion
    /// reference frame and causing spurious detections. The wide-angle physical sensor
    /// never switches lenses — zoom is purely digital on that one sensor.
    static let preferredBackCameraTypes: [AVCaptureDevice.DeviceType] = [
        .builtInWideAngleCamera,
        .builtInDualCamera,
        .builtInDualWideCamera,
        .builtInTripleCamera
    ]

    // MARK: - Internal (visible for testing)

    /// Exposed so tests can flush the queue with `sync {}` to assert state after enqueued work completes.
    let sessionQueue = DispatchQueue(label: "com.mtgscanner.camera-session", qos: .userInitiated)

    /// Set to `true` in tests to simulate a running session without real hardware.
    /// In production this is always driven by `session.isRunning` via `start()`/`stop()`.
    var isSessionReady = false

    /// Set to `true` in tests to skip issuing a real AVCapturePhotoOutput request.
    /// This allows state-machine tests to run without a configured camera pipeline.
    var suppressCaptureForTesting = false

    // MARK: - Private

    private let photoOutput = AVCapturePhotoOutput()
    private var isCaptureInFlight = false
    private var captureGeneration = 0
    private var _activeHandler: PhotoCaptureHandler?
    private(set) var captureDevice: AVCaptureDevice?
    private var maxPhotoDimensions = CMVideoDimensions(width: 0, height: 0)

    private static let capturePointOfInterest = CGPoint(x: 0.5, y: 0.5)
    private var focusPoint = CGPoint(x: 0.5, y: 0.5)
    private var focusSettlingState: FocusSettlingState?
    private var focusObservations: [NSKeyValueObservation] = []
    private var focusObservationGeneration = 0
    private static let captureSettlePollInterval: TimeInterval = 0.05
    private static let focusLogger = Logger(subsystem: "com.mtgscanner", category: "CameraFocus")

    // MARK: - Setup

    /// Configures the capture session.
    ///
    /// Must be called once before `start()`. Safe to call from any queue.
    func configure(camera: AutoScanCamera = .standard) {
        sessionQueue.async { [weak self] in
            self?.configureOnSessionQueue(camera: camera)
        }
    }

    private func configureOnSessionQueue(camera: AutoScanCamera) {
        session.beginConfiguration()
        defer {
            session.commitConfiguration()
            if let device = captureDevice {
                observeAdjustments(device)
                if !configureFocus(device, point: focusPoint) { print("[Camera] Could not configure continuous focus") }
                print("[Camera] \(camera.rawValue): \(device.deviceType.rawValue), " +
                      "minimum focus distance \(device.minimumFocusDistance) mm")
            }
        }

        session.sessionPreset = .hd1920x1080

        guard
            let device = makeBackCameraDevice(camera: camera),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: sessionQueue)

        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        guard session.canAddOutput(photoOutput) else { return }
        session.addOutput(photoOutput)

        if device.activeFormat.isHighPhotoQualitySupported {
            photoOutput.maxPhotoQualityPrioritization = .quality
        }

        if let largest = Self.largestPhotoDimensions(in: device.activeFormat.supportedMaxPhotoDimensions) {
            photoOutput.maxPhotoDimensions = largest
            maxPhotoDimensions = largest
        }
        captureDevice = device
    }

    private func makeBackCameraDevice(camera: AutoScanCamera) -> AVCaptureDevice? {
        let closeUp = camera == .automatic ? AutoScanCamera.closeUpDevice() : nil
        if camera.preferredDeviceType(closeUpAvailable: closeUp != nil) == .builtInUltraWideCamera {
            return closeUp
        }
        for deviceType in Self.preferredBackCameraTypes {
            if let device = AVCaptureDevice.default(deviceType, for: .video, position: .back) {
                return device
            }
        }
        return nil
    }

    static func largestPhotoDimensions(in dimensions: [CMVideoDimensions]) -> CMVideoDimensions? {
        dimensions.max { lhs, rhs in
            Int64(lhs.width) * Int64(lhs.height) < Int64(rhs.width) * Int64(rhs.height)
        }
    }

    // MARK: - Photo Capture

    /// Waits briefly for focus, then captures even if continuous adjustment is still active.
    /// Completion is delivered on the main queue, including cancellation and readiness failures.
    func captureFocusedPhoto(
        focusPoint: CGPoint?, completion: @escaping @Sendable (CameraCaptureResult) -> Void
    ) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.isSessionReady, !self.isCaptureInFlight else {
                DispatchQueue.main.async { completion(.failure(.unavailable)) }
                return
            }
            self.isCaptureInFlight = true
            self.captureGeneration &+= 1
            let handler = PhotoCaptureHandler(
                generation: self.captureGeneration,
                maxPhotoDimensions: self.maxPhotoDimensions,
                completion: completion,
                sessionQueue: self.sessionQueue,
                onDone: { [weak self] handler in self?.captureDidFinish(handler: handler) }
            )
            self._activeHandler = handler
            self.captureWhenFocused(handler: handler, point: focusPoint ?? Self.capturePointOfInterest)
        }
    }

    /// Only clears manager-level in-flight state if `handler` is still the active one.
    /// Prevents a stale or cancelled handler from clobbering a newer capture's state.
    private func captureDidFinish(handler: PhotoCaptureHandler) {
        guard _activeHandler === handler else { return }
        isCaptureInFlight = false
        _activeHandler = nil
    }

    /// Test-only accessor for queue-confined capture state.
    func activeHandlerForTesting() -> AnyObject? {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        return _activeHandler
    }

    /// Test-only accessor for queue-confined capture state.
    func isCaptureInFlightForTesting() -> Bool {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        return isCaptureInFlight
    }

    /// Test-only hook that exercises the same stale-handler guard used by AVFoundation callbacks.
    func finishCaptureForTesting(handler: AnyObject?) {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        guard let handler = handler as? PhotoCaptureHandler else { return }
        captureDidFinish(handler: handler)
    }

}

extension CameraSessionManager {
    /// Runs on the session queue. Failed configuration leaves the target eligible for retry.
    func prepareFocus(at point: CGPoint, configure: () -> Bool) -> Bool {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        if focusSettlingState != nil, !CameraFocus.needsRetargeting(from: focusPoint, to: point) {
            return true
        }
        guard configure() else { return false }
        focusPoint = point
        focusSettlingState = FocusSettlingState(startedAt: ProcessInfo.processInfo.systemUptime)
        return true
    }

    func focus(on point: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let self, !self.isCaptureInFlight, let device = self.captureDevice else { return }
            if !self.configureFocus(device, point: point) {
                print("[Camera] Could not retarget continuous focus")
            }
        }
    }
}

// MARK: - Focus helpers

private extension CameraSessionManager {

    func configureFocus(_ device: AVCaptureDevice, point: CGPoint) -> Bool {
        prepareFocus(at: point) {
            do {
                try device.lockForConfiguration()
            } catch {
                Self.focusLogger.error("Focus configuration failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
            defer { device.unlockForConfiguration() }
            configurePointsOfInterest(device, point: point)
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            return true
        }
    }

    func configurePointsOfInterest(_ device: AVCaptureDevice, point: CGPoint) {
        if device.isFocusPointOfInterestSupported {
            device.focusPointOfInterest = point
        }
        if device.isExposurePointOfInterestSupported {
            device.exposurePointOfInterest = point
        }
    }

    func captureWhenFocused(handler: PhotoCaptureHandler, point: CGPoint) {
        guard !suppressCaptureForTesting else { return }
        guard let device = captureDevice else {
            handler.fail(.unavailable)
            return
        }
        guard configureFocus(device, point: point) else {
            handler.fail(.focusConfigurationFailed)
            return
        }
        waitForFocus(
            handler: handler, deadline: ProcessInfo.processInfo.systemUptime + 0.5
        )
    }

    func observeAdjustments(_ device: AVCaptureDevice) {
        clearFocusWait()
        let generation = focusObservationGeneration
        focusObservations = [device.observe(\.isAdjustingFocus, options: [.new]) { [weak self] _, change in
            guard change.newValue == true else { return }
            self?.sessionQueue.async { [weak self] in
                guard let self, self.focusObservationGeneration == generation else { return }
                self.focusSettlingState?.recordAdjustment()
            }
        }]
    }

    func clearFocusWait() {
        focusObservationGeneration &+= 1
        focusObservations.removeAll()
        focusSettlingState = nil
    }

    func waitForFocus(handler: PhotoCaptureHandler, deadline: TimeInterval) {
        guard handler.generation == captureGeneration, _activeHandler === handler else { return }
        guard let device = captureDevice else {
            handler.fail(.unavailable)
            return
        }
        guard let decision = focusSettlingState?.evaluate(
            isAdjusting: device.isAdjustingFocus,
            at: ProcessInfo.processInfo.systemUptime, deadline: deadline
        ) else {
            Self.focusLogger.error("Capture \(handler.generation): missing prepared focus state")
            handler.fail(.focusConfigurationFailed)
            return
        }
        switch decision {
        case .settled:
            logFocusCapture(handler: handler, device: device, deadline: deadline, settled: true)
            handler.issueCapture(to: photoOutput)
        case .captureAtDeadline:
            logFocusCapture(handler: handler, device: device, deadline: deadline, settled: false)
            handler.issueCapture(to: photoOutput)
        case .waiting:
            sessionQueue.asyncAfter(deadline: .now() + Self.captureSettlePollInterval) { [weak self] in
                self?.waitForFocus(handler: handler, deadline: deadline)
            }
        }
    }

    func logFocusCapture(
        handler: PhotoCaptureHandler, device: AVCaptureDevice, deadline: TimeInterval, settled: Bool
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        let wait = String(format: "%.3f", now - (deadline - 0.5))
        let age = String(format: "%.3f", now - (focusSettlingState?.startedAt ?? now))
        let details = "capture=\(handler.generation) wait=\(wait)s targetAge=\(age)s " +
            "point=(\(focusPoint.x),\(focusPoint.y)) lens=\(device.deviceType.rawValue) " +
            "lensPosition=\(device.lensPosition) focusMode=\(device.focusMode.rawValue) " +
            "adjustingFocus=\(device.isAdjustingFocus) adjustingExposure=\(device.isAdjustingExposure)"
        if settled {
            Self.focusLogger.notice("Focus settled: \(details, privacy: .public)")
        } else {
            Self.focusLogger.warning("Focus deadline fallback: \(details, privacy: .public)")
        }
    }

    func recordFocusReadiness() {
        guard let device = captureDevice else { return }
        focusSettlingState?.record(
            isAdjusting: device.isAdjustingFocus,
            at: ProcessInfo.processInfo.systemUptime
        )
    }
}

// MARK: - Exposure

extension CameraSessionManager {

    /// Sets the exposure bias (EV offset) on the capture device.
    ///
    /// A positive value brightens the image; negative darkens it.
    /// The device clamps the value to its supported range automatically.
    /// Dispatches to the session queue and is safe to call from any thread.
    func setExposureBias(_ bias: Float) {
        sessionQueue.async { [weak self] in
            guard
                let self,
                let device = self.captureDevice,
                device.isExposureModeSupported(.custom) || device.isExposureModeSupported(.continuousAutoExposure)
            else { return }
            guard (try? device.lockForConfiguration()) != nil else { return }
            let clamped = max(device.minExposureTargetBias, min(device.maxExposureTargetBias, bias))
            device.setExposureTargetBias(clamped)
            device.unlockForConfiguration()
        }
    }
}

// MARK: - Torch

extension CameraSessionManager {

    /// Sets the back-camera torch to `level` (0 = off, 0.1–1.0 = on at that brightness).
    ///
    /// Dispatches to the session queue and is safe to call from any thread.
    func setTorchLevel(_ level: Float) {
        sessionQueue.async { [weak self] in
            guard
                let self,
                let device = self.captureDevice,
                device.hasTorch,
                device.isTorchAvailable
            else { return }
            do {
                try device.lockForConfiguration()
                if level <= 0 {
                    device.torchMode = .off
                } else {
                    let clamped = min(level, AVCaptureDevice.maxAvailableTorchLevel)
                    try? device.setTorchModeOn(level: clamped)
                }
                device.unlockForConfiguration()
            } catch { return }
        }
    }
}

// MARK: - Lifecycle

extension CameraSessionManager {

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
            self.isSessionReady = self.session.isRunning && self.captureDevice != nil
            if self.focusSettlingState == nil, let device = self.captureDevice {
                self.observeAdjustments(device)
                if !self.configureFocus(device, point: self.focusPoint) {
                    print("[Camera] Could not restore continuous focus")
                }
            }
        }
    }

    func shutDown() {
        sessionQueue.async { [self] in
            onFrame = nil
            onPixelBuffer = nil
        }
        stop()
    }

    func stop() {
        sessionQueue.async { [self] in
            self.isSessionReady = false
            if self.isCaptureInFlight {
                self.captureGeneration &+= 1
                self._activeHandler?.cancel()
                self._activeHandler = nil
                self.isCaptureInFlight = false
            }
            self.clearFocusWait()
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraSessionManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        recordFocusReadiness()
        onFrame?(sampleBuffer)
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            onPixelBuffer?(pixelBuffer, sampleBuffer.presentationTimeStamp)
        }
    }
}
