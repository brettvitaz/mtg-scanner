import AVFoundation
import UIKit

// swiftlint:disable type_body_length
/// Manages the `AVCaptureSession` lifecycle for real-time card detection.
///
/// Responsibilities:
/// - Configure the best available back camera for 1080p video output.
/// - Deliver `CMSampleBuffer` frames to `onFrame` on the session queue.
/// - Start and stop the session from outside the session queue safely.
final class CameraSessionManager: NSObject, CameraFrameSource, @unchecked Sendable {

    // MARK: - Public

    let session = AVCaptureSession()

    /// Called on the session queue for each delivered video frame.
    var onFrame: ((CMSampleBuffer) -> Void)?

    /// Called on the session queue for each delivered pixel buffer (CameraFrameSource).
    var onPixelBuffer: ((CVPixelBuffer, CMTime) -> Void)?

    static let preferredBackCameraTypes: [AVCaptureDevice.DeviceType] = [
        .builtInTripleCamera,
        .builtInDualWideCamera,
        .builtInDualCamera,
        .builtInWideAngleCamera
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
    private static let captureSettleTimeout: TimeInterval = 1.2
    private static let captureSettlePollInterval: TimeInterval = 0.05

    // MARK: - Setup

    /// Configures the capture session.
    ///
    /// Must be called once before `start()`. Safe to call from any queue.
    func configure() {
        sessionQueue.async { [weak self] in
            self?.configureOnSessionQueue()
        }
    }

    private func configureOnSessionQueue() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .hd1920x1080

        guard
            let device = makeBackCameraDevice(),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return }
        session.addInput(input)
        captureDevice = device
        configureFocus(device)

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
    }

    private func makeBackCameraDevice() -> AVCaptureDevice? {
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

    private func configureFocus(_ device: AVCaptureDevice) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        configurePointsOfInterest(device)
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isAutoFocusRangeRestrictionSupported {
            device.autoFocusRangeRestriction = .near
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        device.unlockForConfiguration()
    }

    private func configurePointsOfInterest(_ device: AVCaptureDevice) {
        if device.isFocusPointOfInterestSupported {
            device.focusPointOfInterest = Self.capturePointOfInterest
        }
        if device.isExposurePointOfInterestSupported {
            device.exposurePointOfInterest = Self.capturePointOfInterest
        }
    }

    // MARK: - Photo Capture

    /// Triggers a still photo capture and returns the captured upload payload via `completion`.
    /// If a capture is already in flight, or the session is not yet running, `completion`
    /// is called immediately with `nil`.
    func capturePhoto(completion: @escaping @Sendable (RecognitionImagePayload?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.isSessionReady, !self.isCaptureInFlight else {
                DispatchQueue.main.async { completion(nil) }
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
            self.lockFocusThenCapture(handler: handler)
        }
    }

    /// Only clears manager-level in-flight state if `handler` is still the active one.
    /// Prevents a stale or cancelled handler from clobbering a newer capture's state.
    private func captureDidFinish(handler: PhotoCaptureHandler) {
        guard _activeHandler === handler else { return }
        isCaptureInFlight = false
        _activeHandler = nil
        restoreContinuousAutoFocus()
    }

    private func lockFocusThenCapture(handler: PhotoCaptureHandler) {
        guard !suppressCaptureForTesting else { return }
        guard let device = captureDevice else {
            handler.issueCapture(to: photoOutput)
            return
        }
        var shouldWaitForSettle = false
        do {
            try device.lockForConfiguration()
            configurePointsOfInterest(device)
            if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
                shouldWaitForSettle = true
            }
            if device.isExposureModeSupported(.autoExpose) {
                device.exposureMode = .autoExpose
                shouldWaitForSettle = true
            }
            device.unlockForConfiguration()
        } catch {
            handler.issueCapture(to: photoOutput)
            return
        }

        guard shouldWaitForSettle else {
            handler.issueCapture(to: photoOutput)
            return
        }

        waitForFocusAndExposureToSettle(handler: handler, startedAt: Date())
    }

    private func waitForFocusAndExposureToSettle(handler: PhotoCaptureHandler, startedAt: Date) {
        guard handler.generation == captureGeneration, _activeHandler === handler else { return }
        guard let device = captureDevice else {
            handler.issueCapture(to: photoOutput)
            return
        }

        let didSettle = !device.isAdjustingFocus && !device.isAdjustingExposure
        let didTimeOut = Date().timeIntervalSince(startedAt) >= Self.captureSettleTimeout
        guard !didSettle, !didTimeOut else {
            handler.issueCapture(to: photoOutput)
            return
        }

        sessionQueue.asyncAfter(deadline: .now() + Self.captureSettlePollInterval) { [weak self] in
            self?.waitForFocusAndExposureToSettle(handler: handler, startedAt: startedAt)
        }
    }

    private func restoreContinuousAutoFocus() {
        guard let device = captureDevice,
              (try? device.lockForConfiguration()) != nil else { return }
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        device.unlockForConfiguration()
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

    // MARK: - Torch

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

    // MARK: - Lifecycle

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
            self.isSessionReady = true
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.isSessionReady = false
            if self.isCaptureInFlight {
                self.captureGeneration &+= 1
                self._activeHandler?.cancel()
                self._activeHandler = nil
                self.isCaptureInFlight = false
                self.restoreContinuousAutoFocus()
            }
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }
}
// swiftlint:enable type_body_length

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraSessionManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        onFrame?(sampleBuffer)
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            onPixelBuffer?(pixelBuffer, sampleBuffer.presentationTimeStamp)
        }
    }
}

// MARK: - Per-capture delegate

/// Owns the completion and AVCapturePhotoCaptureDelegate for exactly one photo capture.
///
/// By making each capture its own delegate, a stale AVFoundation callback can never
/// reach a different capture's completion — it only talks to the object it was given.
///
/// Both `cancel()` and `photoOutput(_:didFinishProcessingPhoto:)` are serialized through
/// `sessionQueue` so the `completion` slot has a single writer at a time.
private final class PhotoCaptureHandler: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {

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

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
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
