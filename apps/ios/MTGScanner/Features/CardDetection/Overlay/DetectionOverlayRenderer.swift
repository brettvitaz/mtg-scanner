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
    private var lastDetections: [DetectedCard] = []

    /// Minimum IoU between a new detection and its matched prior detection before
    /// we consider the position "changed enough" to redraw. Values below this
    /// threshold are treated as stable and the overlay is not updated, suppressing
    /// sub-pixel jitter.
    private static let jitterThreshold: CGFloat = 0.85

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
        // Suppress redraws when detection count is unchanged and all bounding boxes
        // haven't moved significantly — this eliminates sub-pixel jitter.
        if detections.count == lastDetections.count, !detections.isEmpty {
            let allStable = zip(detections, lastDetections).allSatisfy { new, old in
                RectangleFilter.iou(new.boundingBox, old.boundingBox) >= Self.jitterThreshold
            }
            if allStable { return }
        }
        lastDetections = detections

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

    /// Converts a Vision normalized point (origin bottom-left, 0…1) to a point in
    /// the `previewLayer`'s coordinate space.
    ///
    /// Vision normalized coordinates and AVCaptureDevice coordinates share the same
    /// origin (bottom-left) and axis orientation, so `layerPointConverted` handles
    /// the mapping directly without any manual axis flip.
    static func visionToPreview(point: CGPoint, previewLayer: AVCaptureVideoPreviewLayer) -> CGPoint {
        previewLayer.layerPointConverted(fromCaptureDevicePoint: point)
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
