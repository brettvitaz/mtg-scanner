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

    var shouldChangeZoom: ((CGFloat) -> Bool)?
    private(set) var appliedZoom: CGFloat = 1
    // Device boundary injection allows hosted controls to exercise the real zoom path.
    var zoomDevice: CameraZoomDevice?

    var camera: AutoScanCamera = .standard

    // MARK: - Private

    private let sessionManager: CameraSessionManager
    private let engine = CardDetectionEngine()
    private var renderer: DetectionOverlayRenderer?
    private var isVisible = false
    private var desiredTorchLevel: Float = 0
    private var desiredExposureBias: Float = 0

    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let detectionLayer = CALayer()
    private var zoomFactorAtGestureStart: CGFloat = 1.0
    private static let maxZoomFactor: CGFloat = 5.0

    init(sessionManager: CameraSessionManager = CameraSessionManager()) {
        self.sessionManager = sessionManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        sessionManager = CameraSessionManager()
        super.init(coder: coder)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupPreviewLayer()
        setupDetectionLayer()
        setupPinchGesture()
        wireComponents()
        sessionManager.configure(camera: camera)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        sessionManager.start()
        applyTorchLevel(desiredTorchLevel)
        sessionManager.setExposureBias(desiredExposureBias)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        sessionManager.setTorchLevel(0)
        sessionManager.pauseForNavigation()
        renderer?.clear()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        detectionLayer.frame = view.bounds
        updatePreviewOrientation()
        engine.updateIsLandscape(view.bounds.width > view.bounds.height)
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
    }

    func captureFocusedPhoto(
        focusPoint: CGPoint?, completion: @escaping @Sendable (CameraCaptureResult) -> Void
    ) {
        sessionManager.captureFocusedPhoto(focusPoint: focusPoint, completion: completion)
    }

    func focus(on point: CGPoint) {
        sessionManager.focus(on: point)
    }

    func shutDown() {
        onAutoScanFrame = nil
        sessionManager.shutDown()
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
        desiredExposureBias = bias
        guard isVisible else { return }
        sessionManager.setExposureBias(bias)
    }

    // MARK: - Zoom

    /// Applies device-constrained zoom and reports the value only after a successful change.
    func setZoom(_ factor: CGFloat) {
        let target = zoomDevice ?? sessionManager.captureDevice.map(CameraZoomDevice.init)
        guard let target else { return }
        let clamped = Self.clampedZoom(start: factor, scale: 1, max: min(Self.maxZoomFactor, target.maximum))
        guard abs(clamped - appliedZoom) > 0.001 else {
            if factor != clamped { onZoomFactorChanged?(appliedZoom) }
            return
        }
        guard shouldChangeZoom?(clamped) ?? true, target.apply(clamped) else { return }
        appliedZoom = clamped
        onZoomFactorChanged?(clamped)
    }

    private func setupPinchGesture() {
        let recognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(recognizer)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            zoomFactorAtGestureStart = appliedZoom
        case .changed:
            applyPinch(scale: gesture.scale)
        default:
            break
        }
    }

    func applyPinch(scale: CGFloat) {
        setZoom(zoomFactorAtGestureStart * scale)
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
