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
    private var zoneOverlayLayer: CAShapeLayer?

    // MARK: - Init

    init(detectionLayer: CALayer) {
        self.detectionLayer = detectionLayer
        setupZoneOverlay(in: detectionLayer)
    }

    // MARK: - Zone Overlay

    private func setupZoneOverlay(in parent: CALayer?) {
        let layer = CAShapeLayer()
        layer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.6).cgColor
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = 1.5
        layer.lineDashPattern = [6, 4]
        layer.isHidden = true
        layer.actions = [
            "path": NSNull(),
            "hidden": NSNull(),
            "opacity": NSNull()
        ]
        parent?.addSublayer(layer)
        zoneOverlayLayer = layer
    }

    /// Updates the detection zone overlay.
    ///
    /// The zone coordinates are in Vision bottom-left origin space (matching card detections),
    /// converted to layer coordinates for rendering.
    ///
    /// Must be called on the main thread.
    func updateZoneOverlay(zone: DetectionZone?, previewLayer: AVCaptureVideoPreviewLayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard let zone, let layer = zoneOverlayLayer else {
            zoneOverlayLayer?.isHidden = true
            return
        }

        let path = UIBezierPath(rect: rectToLayer(zone.effectiveRect, previewLayer: previewLayer))
        layer.path = path.cgPath
        layer.isHidden = false
    }

    /// Hides the zone overlay.
    func hideZoneOverlay() {
        zoneOverlayLayer?.isHidden = true
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
    /// `layerPointConverted` then handles resizeAspectFill crop and videoRotationAngle
    /// for all device orientations (portrait, landscape left/right, portrait upside-down).
    static func visionPointToLayer(_ point: CGPoint, previewLayer: AVCaptureVideoPreviewLayer) -> CGPoint {
        previewLayer.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: point.x, y: 1.0 - point.y))
    }

    // MARK: - Private Helpers

    private func makeQuadPath(for card: DetectedCard, previewLayer: AVCaptureVideoPreviewLayer) -> UIBezierPath {
        let tl = Self.visionPointToLayer(card.topLeft, previewLayer: previewLayer)
        let tr = Self.visionPointToLayer(card.topRight, previewLayer: previewLayer)
        let br = Self.visionPointToLayer(card.bottomRight, previewLayer: previewLayer)
        let bl = Self.visionPointToLayer(card.bottomLeft, previewLayer: previewLayer)

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

    private func yoloRectToVision(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: 1.0 - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func rectToLayer(_ rect: CGRect, previewLayer: AVCaptureVideoPreviewLayer) -> CGRect {
        let origin = Self.visionPointToLayer(CGPoint(x: rect.minX, y: rect.minY), previewLayer: previewLayer)
        let topRight = Self.visionPointToLayer(CGPoint(x: rect.maxX, y: rect.maxY), previewLayer: previewLayer)
        return CGRect(
            x: origin.x,
            y: topRight.y,
            width: topRight.x - origin.x,
            height: origin.y - topRight.y
        )
    }
}
