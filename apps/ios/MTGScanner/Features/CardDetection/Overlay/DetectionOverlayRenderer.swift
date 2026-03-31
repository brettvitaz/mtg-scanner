import AVFoundation
import UIKit

/// Draws bounding-quad overlays on a detection layer for each detected card.
///
/// Maintains a reusable pool of `CAShapeLayer` instances to avoid add/remove cycles
/// that cause visible flicker at high frame rates. Unused layers are hidden rather
/// than removed. `CATransaction` animations are disabled to prevent path-change
/// interpolation from blurring fast-moving overlays.
final class DetectionOverlayRenderer {

    // MARK: - Private State

    private weak var detectionLayer: CALayer?
    private var layerPool: [CAShapeLayer] = []
    private var lastDetectionCount: Int = -1

    // MARK: - Init

    init(detectionLayer: CALayer) {
        self.detectionLayer = detectionLayer
    }

    // MARK: - Public Update

    /// Refreshes the overlay to match `detections`, converting Vision coordinates
    /// to `previewLayer` screen coordinates.
    ///
    /// Must be called on the main thread.
    func update(
        detections: [DetectedCard],
        previewLayer: AVCaptureVideoPreviewLayer,
        interfaceOrientation: UIInterfaceOrientation
    ) {
        lastDetectionCount = detections.count

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        growPoolIfNeeded(to: detections.count, in: detectionLayer)

        for (index, card) in detections.enumerated() {
            let layer = layerPool[index]
            let path = makeQuadPath(for: card, previewLayer: previewLayer, orientation: interfaceOrientation)
            layer.path = path.cgPath
            layer.isHidden = false
        }

        // Hide any layers beyond the current detection count.
        for index in detections.count..<layerPool.count {
            layerPool[index].isHidden = true
        }
    }

    /// Hides all overlay layers (call when the session stops).
    func clear() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        layerPool.forEach { $0.isHidden = true }
    }

    // MARK: - Coordinate Transform

    /// Converts a Vision normalized point to a point in the `previewLayer`'s coordinate space.
    ///
    /// When an orientation hint is passed to `VNImageRequestHandler`, Vision returns corners in
    /// the *oriented* image space (not native sensor space). This method un-rotates those
    /// coordinates back to capture device space before calling `layerPointConverted`, which
    /// expects native sensor coordinates (top-left origin, values 0–1).
    ///
    /// Capture device space: origin top-left, x right, y down, values 0–1, native sensor frame.
    /// Vision oriented space: origin bottom-left, values 0–1, relative to the displayed orientation.
    ///
    /// Derivation (rotation of vision-coord `(vx, vy)` → capture device point):
    ///   - `.landscapeRight` (`.up` hint, no rotation):   `(vx, 1-vy)`
    ///   - `.landscapeLeft`  (`.down` hint, 180°):        `(1-vx, vy)`
    ///   - `.portrait`       (`.right` hint, 90° CW):     `(1-vy, 1-vx)`
    ///   - `.portraitUpsideDown` (`.left` hint, 90° CCW): `(vy, vx)`
    static func visionPointToLayer(
        _ point: CGPoint,
        previewLayer: AVCaptureVideoPreviewLayer,
        orientation: UIInterfaceOrientation
    ) -> CGPoint {
        let cdPoint = captureDevicePoint(point, orientation: orientation)
        return previewLayer.layerPointConverted(fromCaptureDevicePoint: cdPoint)
    }

    /// Returns the capture device coordinate for a Vision normalized point in the given orientation.
    ///
    /// Exposed `internal` for unit testing. Production callers use `visionPointToLayer`.
    static func captureDevicePoint(_ visionPoint: CGPoint, orientation: UIInterfaceOrientation) -> CGPoint {
        switch orientation {
        case .landscapeRight:
            return CGPoint(x: visionPoint.x, y: 1.0 - visionPoint.y)
        case .landscapeLeft:
            return CGPoint(x: 1.0 - visionPoint.x, y: visionPoint.y)
        case .portraitUpsideDown:
            return CGPoint(x: visionPoint.y, y: visionPoint.x)
        default: // .portrait (and unknown)
            return CGPoint(x: 1.0 - visionPoint.y, y: 1.0 - visionPoint.x)
        }
    }

    // MARK: - Private Helpers

    private func makeQuadPath(
        for card: DetectedCard,
        previewLayer: AVCaptureVideoPreviewLayer,
        orientation: UIInterfaceOrientation
    ) -> UIBezierPath {
        let tl = Self.visionPointToLayer(card.topLeft, previewLayer: previewLayer, orientation: orientation)
        let tr = Self.visionPointToLayer(card.topRight, previewLayer: previewLayer, orientation: orientation)
        let br = Self.visionPointToLayer(card.bottomRight, previewLayer: previewLayer, orientation: orientation)
        let bl = Self.visionPointToLayer(card.bottomLeft, previewLayer: previewLayer, orientation: orientation)

        let path = UIBezierPath()
        path.move(to: tl)
        path.addLine(to: tr)
        path.addLine(to: br)
        path.addLine(to: bl)
        path.close()
        return path
    }

    private func growPoolIfNeeded(to count: Int, in parent: CALayer?) {
        guard let parent else { return }
        while layerPool.count < count {
            let layer = makeOverlayLayer()
            parent.addSublayer(layer)
            layerPool.append(layer)
        }
    }

    private func makeOverlayLayer() -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.strokeColor = UIColor.systemGreen.cgColor
        layer.fillColor = UIColor.systemGreen.withAlphaComponent(0.15).cgColor
        layer.lineWidth = 2.0
        layer.isHidden = true
        // Disable implicit animations on all animatable properties to prevent
        // path-change interpolation flicker between detection frames.
        layer.actions = [
            "path": NSNull(),
            "hidden": NSNull(),
            "opacity": NSNull(),
            "position": NSNull(),
            "bounds": NSNull()
        ]
        return layer
    }
}
