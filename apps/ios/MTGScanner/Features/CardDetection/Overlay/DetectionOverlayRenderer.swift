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

    /// Converts a Vision normalized point to a point in the `previewLayer`'s coordinate space,
    /// accounting for the current device orientation.
    ///
    /// Vision with `.right` orientation always returns coordinates in the upright portrait space
    /// (origin bottom-left, x right, y up, values 0–1) regardless of device orientation.
    /// The preview layer connection's `videoRotationAngle` tells us how the camera feed has
    /// been rotated to fill the screen, so we apply the inverse mapping:
    ///
    ///   90°  (portrait):        screenX = visionX * W,       screenY = (1-visionY) * H
    ///   0°   (landscape right): screenX = (1-visionY) * W,   screenY = (1-visionX) * H
    ///   180° (landscape left):  screenX = visionY * W,       screenY = visionX * H
    ///   270° (portrait upside-down): screenX = (1-visionX)*W, screenY = visionY*H
    static func visionToPreview(point: CGPoint, previewLayer: AVCaptureVideoPreviewLayer) -> CGPoint {
        let bounds = previewLayer.bounds
        let W = bounds.width, H = bounds.height
        let angle = previewLayer.connection?.videoRotationAngle ?? 90
        switch angle {
        case 0:   return CGPoint(x: (1.0 - point.y) * W, y: (1.0 - point.x) * H)
        case 180: return CGPoint(x: point.y * W,          y: point.x * H)
        case 270: return CGPoint(x: (1.0 - point.x) * W, y: point.y * H)
        default:  return CGPoint(x: point.x * W,          y: (1.0 - point.y) * H) // 90° portrait
        }
    }

    // MARK: - Private Helpers

    private func makeQuadPath(for card: DetectedCard, previewLayer: AVCaptureVideoPreviewLayer) -> UIBezierPath {
        // Convert all four Vision corners to screen coordinates.
        let points = [card.topLeft, card.topRight, card.bottomRight, card.bottomLeft]
            .map { Self.visionToPreview(point: $0, previewLayer: previewLayer) }

        // Sort into convex drawing order (top-left → top-right → bottom-right → bottom-left
        // in screen space) so the polygon never self-intersects regardless of card tilt.
        let ordered = convexOrder(points)

        let path = UIBezierPath()
        path.move(to: ordered[0])
        for pt in ordered.dropFirst() { path.addLine(to: pt) }
        path.close()
        return path
    }

    /// Returns the four points sorted in clockwise screen order starting from the
    /// top-left point (smallest x+y sum).
    private func convexOrder(_ pts: [CGPoint]) -> [CGPoint] {
        guard pts.count == 4 else { return pts }
        // Find centroid.
        let cx = pts.map(\.x).reduce(0, +) / 4
        let cy = pts.map(\.y).reduce(0, +) / 4
        let center = CGPoint(x: cx, y: cy)
        // Sort by angle from centroid (clockwise in screen coords where y increases downward).
        let sorted = pts.sorted { a, b in
            let angleA = atan2(a.y - center.y, a.x - center.x)
            let angleB = atan2(b.y - center.y, b.x - center.x)
            return angleA < angleB
        }
        // Rotate so the top-left point (min x+y) is first.
        guard let startIdx = sorted.indices.min(by: { sorted[$0].x + sorted[$0].y < sorted[$1].x + sorted[$1].y }) else {
            return sorted
        }
        return Array(sorted[startIdx...] + sorted[..<startIdx])
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
