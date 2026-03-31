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

    /// The camera buffer is 1920×1080 (16:9) per CameraSessionManager's `.hd1920x1080` preset.
    /// In Vision normalized coordinates (0–1), 1 unit in x = 1920 pixels and 1 unit in y = 1080
    /// pixels. Distances are therefore NOT square-pixel-equal: x-distances are compressed by 9/16
    /// relative to y-distances.
    ///
    /// When a card is portrait-oriented (upright) in the landscape buffer, its normalized short/long
    /// edge ratio is targetAspectRatio × (1080/1920) ≈ 0.402 — well below the landscape-oriented
    /// card ratio of ≈ 0.785. A second acceptance band covers this case so that vertical cards are
    /// detected when the device is held in landscape.
    ///
    /// Derivation: for a 63mm-wide × 88mm-tall card in the 1920×1080 buffer —
    ///   norm_width  = 63k / 1920,  norm_height = 88k / 1080
    ///   ratio = norm_width / norm_height = (63/88) × (1080/1920) ≈ 0.402
    private static let portraitInBufferRatio: CGFloat = targetAspectRatio * (1080.0 / 1920.0)

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
    ///
    /// Two acceptance bands cover both device orientations:
    /// - Landscape-in-buffer (~0.785): card's long axis is horizontal in the sensor (portrait phone).
    /// - Portrait-in-buffer (~0.402): card's long axis is vertical in the sensor (landscape phone).
    ///   The 16:9 buffer compresses normalized x-distances by 9/16, shifting the observed ratio to
    ///   targetAspectRatio × (1080/1920) ≈ 0.402.
    private func isCardAspectRatio(_ obs: VNRectangleObservation) -> Bool {
        let topEdge = dist(obs.topLeft, obs.topRight)
        let bottomEdge = dist(obs.bottomLeft, obs.bottomRight)
        let leftEdge = dist(obs.topLeft, obs.bottomLeft)
        let rightEdge = dist(obs.topRight, obs.bottomRight)

        let avgWidth = (topEdge + bottomEdge) / 2
        let avgHeight = (leftEdge + rightEdge) / 2
        guard avgWidth > 0, avgHeight > 0 else { return false }

        let ratio = min(avgWidth, avgHeight) / max(avgWidth, avgHeight)

        let landscapeLower = Self.targetAspectRatio * (1 - Self.aspectRatioTolerance)
        let landscapeUpper = Self.targetAspectRatio * (1 + Self.aspectRatioTolerance)
        let portraitLower = Self.portraitInBufferRatio * (1 - Self.aspectRatioTolerance)
        let portraitUpper = Self.portraitInBufferRatio * (1 + Self.aspectRatioTolerance)

        return (ratio >= landscapeLower && ratio <= landscapeUpper)
            || (ratio >= portraitLower && ratio <= portraitUpper)
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
