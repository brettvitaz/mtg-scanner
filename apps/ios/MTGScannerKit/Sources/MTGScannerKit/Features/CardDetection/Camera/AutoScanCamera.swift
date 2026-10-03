import AVFoundation

enum AutoScanCamera: String, Sendable {
    case standard
    case automatic

    func preferredDeviceType(closeUpAvailable: Bool) -> AVCaptureDevice.DeviceType {
        self == .automatic && closeUpAvailable ? .builtInUltraWideCamera : .builtInWideAngleCamera
    }

    static func closeUpDevice() -> AVCaptureDevice? {
        guard let device = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back),
              device.isFocusModeSupported(.autoFocus), device.isFocusModeSupported(.continuousAutoFocus),
              supportsCapture(device), !device.activeFormat.supportedMaxPhotoDimensions.isEmpty else { return nil }
        return device
    }

    private static func supportsCapture(_ device: AVCaptureDevice) -> Bool {
        guard let input = try? AVCaptureDeviceInput(device: device) else { return false }
        let session = AVCaptureSession()
        let video = AVCaptureVideoDataOutput()
        let photo = AVCapturePhotoOutput()
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input) else { return false }
        session.addInput(input)
        guard session.canSetSessionPreset(.hd1920x1080), session.canAddOutput(video) else { return false }
        session.sessionPreset = .hd1920x1080
        session.addOutput(video)
        guard session.canAddOutput(photo) else { return false }
        session.addOutput(photo)
        return true
    }
}
