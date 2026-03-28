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
    func update(detections: [DetectedCard], previewLayer: AVCaptureVideoPreviewLayer) {
        lastDetectionCount = detections.count

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        growPoolIfNeeded(to: detections.count, in: detectionLayer)

        for (index, card) in detections.enumerated() {
            let layer = layerPool[index]
            let path = makeQuadPath(for: card, previewLayer: previewLayer)
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
    /// Vision returns corners in normalized image coordinates: origin bottom-left, x right, y up,
    /// values 0–1, relative to the native (landscape) pixel buffer passed to the handler.
    ///
    /// `layerPointConverted(fromCaptureDevicePoint:)` expects capture device space:
    /// origin top-left, x right, y down, values 0–1 in the native sensor frame.
    ///
    /// The only difference is Y-axis direction, so we flip Y before converting.
    /// `layerPointConverted` then handles resizeAspectFill crop and videoRotationAngle.
    static func visionPointToLayer(_ point: CGPoint, previewLayer: AVCaptureVideoPreviewLayer) -> CGPoint {
        previewLayer.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: point.x, y: 1.0 - point.y))
    }

    // MARK: - Private Helpers

    private func makeQuadPath(for card: DetectedCard, previewLayer: AVCaptureVideoPreviewLayer) -> UIBezierPath {
        let tl = Self.visionPointToLayer(card.topLeft,     previewLayer: previewLayer)
        let tr = Self.visionPointToLayer(card.topRight,    previewLayer: previewLayer)
        let br = Self.visionPointToLayer(card.bottomRight, previewLayer: previewLayer)
        let bl = Self.visionPointToLayer(card.bottomLeft,  previewLayer: previewLayer)

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
            "bounds": NSNull(),
        ]
        return layer
    }
}
