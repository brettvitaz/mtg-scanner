import AVFoundation

/// Manages the `AVCaptureSession` lifecycle for real-time card detection.
///
/// Responsibilities:
/// - Configure the back wide-angle camera for 1080p video output.
/// - Deliver `CMSampleBuffer` frames to `onFrame` on the session queue.
/// - Start and stop the session from outside the session queue safely.
final class CameraSessionManager: NSObject, @unchecked Sendable {

    // MARK: - Public

    let session = AVCaptureSession()

    /// Called on the session queue for each delivered video frame.
    var onFrame: ((CMSampleBuffer) -> Void)?

    // MARK: - Private

    private let sessionQueue = DispatchQueue(label: "com.mtgscanner.camera-session", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private var photoCaptureCompletion: ((Data?) -> Void)?
    private var isCaptureInFlight = false
    private(set) var captureDevice: AVCaptureDevice?
    private var maxPhotoDimensions = CMVideoDimensions(width: 0, height: 0)

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
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
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

        if let largest = device.activeFormat.supportedMaxPhotoDimensions.last {
            photoOutput.maxPhotoDimensions = largest
            maxPhotoDimensions = largest
        }
    }

    private func configureFocus(_ device: AVCaptureDevice) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        if device.isFocusPointOfInterestSupported {
            device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
        }
        if device.isAutoFocusRangeRestrictionSupported {
            device.autoFocusRangeRestriction = .near
        }
        device.unlockForConfiguration()
    }

    // MARK: - Photo Capture

    /// Triggers a still photo capture and returns JPEG data via `completion`.
    /// If a capture is already in flight, `completion` is called immediately with `nil`.
    func capturePhoto(completion: @escaping @Sendable (Data?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.isCaptureInFlight else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.isCaptureInFlight = true
            self.photoCaptureCompletion = completion
            self.lockFocusThenCapture()
        }
    }

    private func lockFocusThenCapture() {
        guard let device = captureDevice,
              device.isFocusModeSupported(.autoFocus) else {
            captureWithCurrentSettings()
            return
        }
        do {
            try device.lockForConfiguration()
            device.focusMode = .autoFocus
            device.unlockForConfiguration()
        } catch {
            captureWithCurrentSettings()
            return
        }
        sessionQueue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.captureWithCurrentSettings()
        }
    }

    private func captureWithCurrentSettings() {
        let settings = AVCapturePhotoSettings()
        if maxPhotoDimensions.width > 0 {
            settings.maxPhotoDimensions = maxPhotoDimensions
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func restoreContinuousAutoFocus() {
        guard let device = captureDevice,
              (try? device.lockForConfiguration()) != nil else { return }
        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }
        device.unlockForConfiguration()
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
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.isCaptureInFlight {
                let pending = self.photoCaptureCompletion
                self.photoCaptureCompletion = nil
                self.isCaptureInFlight = false
                DispatchQueue.main.async { pending?(nil) }
            }
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
        onFrame?(sampleBuffer)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraSessionManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        let completion = photoCaptureCompletion
        photoCaptureCompletion = nil
        isCaptureInFlight = false
        restoreContinuousAutoFocus()
        DispatchQueue.main.async { completion?(data) }
    }
}
