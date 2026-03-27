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

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: sessionQueue)

        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        // Rotate the pixel buffer to portrait before delivery so that Vision
        // coordinates and preview layer coordinates share the same orientation.
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
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
