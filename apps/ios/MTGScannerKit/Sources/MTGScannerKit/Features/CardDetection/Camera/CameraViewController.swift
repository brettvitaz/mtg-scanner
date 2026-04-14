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
    /// Called on the main thread whenever the zoom factor changes.
    var onZoomFactorChanged: ((CGFloat) -> Void)?
    /// Called on the session queue for every camera frame when in Auto Scan mode.
    ///
    /// Used by `AutoScanViewModel` to feed frames into `CardPresenceTracker`.
    /// Set to `nil` when not in Auto Scan mode to avoid unnecessary overhead.
    var onAutoScanFrame: ((CMSampleBuffer) -> Void)?
    /// Detection zone for filtering card detections in auto-scan mode.
    var detectionZone: DetectionZone? {
        didSet {
            updateZoneOverlay()
        }
    }

    // MARK: - Private

    private let sessionManager = CameraSessionManager()
    private let engine = CardDetectionEngine()
    private var renderer: DetectionOverlayRenderer?
    private var isVisible = false
    private var desiredTorchLevel: Float = 0

    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let detectionLayer = CALayer()
    private var zoomFactorAtGestureStart: CGFloat = 1.0
    private static let maxZoomFactor: CGFloat = 5.0

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupPreviewLayer()
        setupDetectionLayer()
        setupPinchGesture()
        wireComponents()
        sessionManager.configure()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        sessionManager.start()
        applyTorchLevel(desiredTorchLevel)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        sessionManager.setTorchLevel(0)
        sessionManager.stop()
        renderer?.clear()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        detectionLayer.frame = view.bounds
        updatePreviewOrientation()
        engine.updateIsLandscape(view.bounds.width > view.bounds.height)
        updateZoneOverlay()
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
        engine.updateDetectionMode(mode)
        if mode == .auto {
            renderer?.clear()
        }
        updateZoneOverlay()
    }

    func capturePhoto(completion: @escaping @Sendable (RecognitionImagePayload?) -> Void) {
        sessionManager.capturePhoto(completion: completion)
    }

    // MARK: - Torch

    /// Sets the torch brightness. Level 0 turns the torch off; 0.1–1.0 turns it on at that brightness.
    func setTorchLevel(_ level: Float) {
        desiredTorchLevel = level
        guard isVisible else { return }
        applyTorchLevel(level)
    }

    private func applyTorchLevel(_ level: Float) {
        sessionManager.setTorchLevel(level)
    }

    // MARK: - Exposure

    /// Sets the exposure bias (EV offset). Positive = brighter, negative = darker.
    func setExposureBias(_ bias: Float) {
        sessionManager.setExposureBias(bias)
    }

    // MARK: - Zone Overlay

    private func updateZoneOverlay() {
        guard let previewLayer else { return }
        let zoneToShow = detectionZone ?? .fullFrame
        renderer?.updateZoneOverlay(zone: zoneToShow, previewLayer: previewLayer)
    }

    // MARK: - Zoom

    /// Sets the camera zoom to `factor`, animating smoothly via AVFoundation ramp.
    func setZoom(_ factor: CGFloat) {
        guard let device = sessionManager.captureDevice else { return }
        let maxFactor = min(Self.maxZoomFactor, device.activeFormat.videoMaxZoomFactor)
        let clamped = max(1.0, min(maxFactor, factor))
        guard (try? device.lockForConfiguration()) != nil else { return }
        device.ramp(toVideoZoomFactor: clamped, withRate: 8.0)
        device.unlockForConfiguration()
    }

    private func setupPinchGesture() {
        let recognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(recognizer)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let device = sessionManager.captureDevice else { return }
        switch gesture.state {
        case .began:
            zoomFactorAtGestureStart = device.videoZoomFactor
        case .changed:
            applyZoom(scale: gesture.scale, to: device)
        default:
            break
        }
    }

    private func applyZoom(scale: CGFloat, to device: AVCaptureDevice) {
        let desired = Self.clampedZoom(
            start: zoomFactorAtGestureStart, scale: scale,
            max: min(Self.maxZoomFactor, device.activeFormat.videoMaxZoomFactor)
        )
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = desired
            device.unlockForConfiguration()
        } catch { return }
        onZoomFactorChanged?(desired)
    }

    static func clampedZoom(start: CGFloat, scale: CGFloat, max maxFactor: CGFloat) -> CGFloat {
        Swift.max(1.0, Swift.min(maxFactor, start * scale))
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
            self?.onAutoScanFrame?(sampleBuffer)
        }

        engine.onDetection = { [weak self] cards in
            guard let self, let previewLayer = self.previewLayer else { return }
            // Only show green detection overlay in scan mode, not auto mode (which uses YOLO)
            if self.engine.currentDetectionMode == .scan {
                self.renderer?.update(detections: cards, previewLayer: previewLayer)
            }
            self.onDetectedCardsChanged?(cards)
        }
    }
}
