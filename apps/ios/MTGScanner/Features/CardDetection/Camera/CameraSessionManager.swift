import AVFoundation

/// Manages the `AVCaptureSession` lifecycle for real-time card detection.
///
/// Responsibilities:
/// - Configure the back wide-angle camera for 1080p video output.
/// - Deliver `CMSampleBuffer` frames to `onFrame` on the session queue.
/// - Start and stop the session from outside the session queue safely.
final class CameraSessionManager: NSObject {

    // MARK: - Public

    let session = AVCaptureSession()

    /// Called on the session queue for each delivered video frame.
    var onFrame: ((CMSampleBuffer) -> Void)?

    // MARK: - Private

    private let sessionQueue = DispatchQueue(label: "com.mtgscanner.camera-session", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private var photoCaptureCompletion: ((Data?) -> Void)?
    private(set) var captureDevice: AVCaptureDevice?

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

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return
        }
        session.addInput(input)
        captureDevice = device

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: sessionQueue)

        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
    }

    // MARK: - Photo Capture

    /// Triggers a still photo capture and returns JPEG data via `completion`.
    /// Must be called from the main thread.
    func capturePhoto(completion: @escaping (Data?) -> Void) {
        photoCaptureCompletion = completion
        let settings = AVCapturePhotoSettings()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
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
            guard let self, self.session.isRunning else { return }
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
        DispatchQueue.main.async { completion?(data) }
    }
}
