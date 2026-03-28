import CoreGraphics
import Vision

/// Filters and deduplicates `VNRectangleObservation` results for MTG card detection.
///
/// Responsibilities:
/// - Accept observations whose aspect ratio matches a standard MTG card (63mm × 88mm ≈ 0.716).
/// - Suppress overlapping detections using IoU-based Non-Maximum Suppression (NMS).
/// - Re-sort accepted observations in reading order (top-left to bottom-right).
struct RectangleFilter {

    // MARK: - Constants

    /// Standard MTG card portrait aspect ratio (short side / long side = 63 / 88 ≈ 0.714).
    static let targetAspectRatio: CGFloat = 63.0 / 88.0

    /// Relative tolerance applied to `targetAspectRatio` on each side.
    /// Accommodates slight perspective distortion and detection imprecision
    /// while rejecting square objects (coasters, books, etc.).
    static let aspectRatioTolerance: CGFloat = 0.20

    /// Minimum Vision confidence required to consider an observation.
    static let minConfidence: Float = 0.4

    /// Minimum aspect ratio for VNDetectRectanglesRequest.
    /// Vision uses bounding-box width/height which can be distorted for rotated cards,
    /// so these are wider than the edge-based filter to avoid premature rejection.
    static let visionMinAspectRatio: Float = 0.30

    /// Maximum aspect ratio for VNDetectRectanglesRequest.
    /// Reciprocal of visionMinAspectRatio to cover cards rotated in both directions.
    static let visionMaxAspectRatio: Float = Float(1.0 / Double(visionMinAspectRatio))

    /// IoU threshold above which two observations are treated as duplicates.
    static let iouThreshold: CGFloat = 0.45

    // MARK: - Public API

    /// Returns filtered, deduplicated, and sorted observations from the given array.
    ///
    /// 1. Drops observations below `minConfidence`.
    /// 2. Drops observations whose aspect ratio falls outside the card range.
    /// 3. Applies IoU-based NMS (higher-confidence observation wins ties).
    /// 4. Re-sorts in top-left → bottom-right reading order.
    func filter(_ observations: [VNRectangleObservation]) -> [VNRectangleObservation] {
        let candidates = observations
            .filter { $0.confidence >= Self.minConfidence }
            .filter { isCardAspectRatio($0) }
            .sorted { $0.confidence > $1.confidence }

        var accepted: [VNRectangleObservation] = []
        for obs in candidates {
            let isDuplicate = accepted.contains { Self.iou(obs.boundingBox, $0.boundingBox) > Self.iouThreshold }
            if !isDuplicate {
                accepted.append(obs)
            }
        }

        accepted.sort { a, b in
            let ay = a.boundingBox.minY
            let by = b.boundingBox.minY
            if abs(ay - by) > 0.05 { return ay < by }
            return a.boundingBox.minX < b.boundingBox.minX
        }

        return accepted
    }

    // MARK: - Helpers

    /// Returns true when the observation's edge aspect ratio matches an MTG card.
    ///
    /// Uses the quad's corner points to compute actual edge lengths rather than the
    /// axis-aligned bounding box, which distorts the ratio for slightly rotated cards.
    /// Only accepts cards roughly aligned with the camera orientation — landscape cards
    /// are intentionally excluded to reduce false positives.
    private func isCardAspectRatio(_ obs: VNRectangleObservation) -> Bool {
        let topEdge = dist(obs.topLeft, obs.topRight)
        let bottomEdge = dist(obs.bottomLeft, obs.bottomRight)
        let leftEdge = dist(obs.topLeft, obs.bottomLeft)
        let rightEdge = dist(obs.topRight, obs.bottomRight)

        let avgWidth = (topEdge + bottomEdge) / 2
        let avgHeight = (leftEdge + rightEdge) / 2
        guard avgWidth > 0, avgHeight > 0 else { return false }

        let ratio = min(avgWidth, avgHeight) / max(avgWidth, avgHeight)
        let lower = Self.targetAspectRatio * (1 - Self.aspectRatioTolerance)
        let upper = Self.targetAspectRatio * (1 + Self.aspectRatioTolerance)
        return ratio >= lower && ratio <= upper
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// Intersection-over-union of two axis-aligned rectangles in normalized coordinates.
    static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let ix = max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX))
        let iy = max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
        let intersection = ix * iy
        let union = a.width * a.height + b.width * b.height - intersection
        return union > 0 ? intersection / union : 0
    }
}
