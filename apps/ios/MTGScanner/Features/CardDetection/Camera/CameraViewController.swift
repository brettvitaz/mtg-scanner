import AVFoundation
import UIKit

/// UIViewController that hosts the camera preview and card detection overlays.
///
/// Layer hierarchy:
/// ```
/// view.layer
///   ├─ previewLayer  (AVCaptureVideoPreviewLayer — camera feed)
///   └─ detectionLayer (CALayer — overlay container, same frame as previewLayer)
/// ```
///
/// Wiring:
/// - `sessionManager.onFrame` → `engine.processFrame`
/// - `engine.onDetection` → `renderer.update` (dispatched to main by the engine)
final class CameraViewController: UIViewController {

    // MARK: - Public

    /// Called on the main thread whenever the detected card list changes.
    var onDetectedCardsChanged: (([DetectedCard]) -> Void)?

    // MARK: - Private

    private let sessionManager = CameraSessionManager()
    private let engine = CardDetectionEngine()
    private var renderer: DetectionOverlayRenderer?

    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let detectionLayer = CALayer()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupPreviewLayer()
        setupDetectionLayer()
        wireComponents()
        sessionManager.configure()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        sessionManager.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionManager.stop()
        renderer?.clear()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        detectionLayer.frame = view.bounds
        updatePreviewOrientation()
    }

    // MARK: - Orientation

    /// Rotates the preview layer connection to match the current interface orientation,
    /// so the camera feed always appears upright regardless of device orientation.
    ///
    /// The data output connection is NOT rotated — pixel buffers are always delivered
    /// in the native landscape orientation for Vision processing.
    private func updatePreviewOrientation() {
        guard let connection = previewLayer?.connection,
              connection.isVideoRotationAngleSupported(90) else { return }
        let angle: CGFloat
        switch view.window?.windowScene?.interfaceOrientation {
        case .landscapeLeft:            angle = 180
        case .landscapeRight:           angle = 0
        case .portraitUpsideDown:       angle = 270
        default:                        angle = 90   // portrait
        }
        connection.videoRotationAngle = angle
    }

    // MARK: - Public API

    func updateDetectionMode(_ mode: DetectionMode) {
        engine.detectionMode = mode
    }

    // MARK: - Setup

    private func setupPreviewLayer() {
        let layer = AVCaptureVideoPreviewLayer(session: sessionManager.session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    private func setupDetectionLayer() {
        detectionLayer.frame = view.bounds
        view.layer.addSublayer(detectionLayer)
        renderer = DetectionOverlayRenderer(detectionLayer: detectionLayer)
    }

    private func wireComponents() {
        sessionManager.onFrame = { [weak self] sampleBuffer in
            self?.engine.processFrame(sampleBuffer)
        }

        engine.onDetection = { [weak self] cards in
            guard let self, let previewLayer = self.previewLayer else { return }
            self.renderer?.update(detections: cards, previewLayer: previewLayer)
            self.onDetectedCardsChanged?(cards)
        }
    }
}
