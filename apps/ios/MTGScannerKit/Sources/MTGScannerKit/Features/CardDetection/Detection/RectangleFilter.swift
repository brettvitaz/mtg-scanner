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

    /// Relative tolerance applied to the target ratio on each side.
    /// Accommodates slight perspective distortion and detection imprecision
    /// while rejecting square objects (coasters, books, etc.).
    static let aspectRatioTolerance: CGFloat = 0.20

    /// The camera buffer is 1920×1080 (16:9) per CameraSessionManager's `.hd1920x1080` preset.
    /// In Vision normalized coordinates (0–1), 1 unit in x = 1920 pixels but 1 unit in y = only
    /// 1080 pixels. x-distances are therefore compressed by 9/16 relative to y-distances.
    ///
    /// When the device is in portrait, a card standing upright has its long axis horizontal in
    /// the sensor, yielding an observed normalized ratio ≈ 0.785 (accepted by the standard band).
    ///
    /// When the device is in landscape, a card standing upright has its long axis vertical in the
    /// sensor, yielding:
    ///   norm_width = 63k/1920,  norm_height = 88k/1080
    ///   ratio = (63/88) × (1080/1920) ≈ 0.402
    ///
    /// `portraitInBufferRatio` is the center of the second band used only in landscape mode.
    /// Only ONE band is active at a time (chosen by `isLandscape`) to keep false positives low.
    static let portraitInBufferRatio: CGFloat = targetAspectRatio * (1080.0 / 1920.0)

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
    /// `isLandscape` selects which aspect ratio band is active:
    /// - `false` (portrait device): accepts observations whose normalized ratio falls in the
    ///   landscape-in-buffer range centered on `targetAspectRatio` (~0.716, observed ≈ 0.785).
    /// - `true` (landscape device): accepts observations whose normalized ratio falls in the
    ///   portrait-in-buffer range centered on `portraitInBufferRatio` (~0.402).
    ///
    /// Steps:
    /// 1. Drops observations below `minConfidence`.
    /// 2. Drops observations whose aspect ratio falls outside the active band.
    /// 3. Applies IoU-based NMS (higher-confidence observation wins ties).
    /// 4. Re-sorts in top-left → bottom-right reading order.
    func filter(_ observations: [VNRectangleObservation], isLandscape: Bool) -> [VNRectangleObservation] {
        let candidates = observations
            .filter { $0.confidence >= Self.minConfidence }
            .filter { isCardAspectRatio($0, isLandscape: isLandscape) }
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

    /// Returns true when the observation's edge aspect ratio matches an MTG card in the current
    /// device orientation.
    ///
    /// Uses the quad's corner points to compute actual edge lengths rather than the axis-aligned
    /// bounding box, which distorts the ratio for slightly rotated cards.
    ///
    /// In portrait mode the card's long axis is horizontal in the 16:9 buffer (ratio ≈ 0.785).
    /// In landscape mode the card's long axis is vertical in the buffer (ratio ≈ 0.402 due to
    /// the non-square pixel normalization). Only one band is tested per call.
    private func isCardAspectRatio(_ obs: VNRectangleObservation, isLandscape: Bool) -> Bool {
        let topEdge = dist(obs.topLeft, obs.topRight)
        let bottomEdge = dist(obs.bottomLeft, obs.bottomRight)
        let leftEdge = dist(obs.topLeft, obs.bottomLeft)
        let rightEdge = dist(obs.topRight, obs.bottomRight)

        let avgWidth = (topEdge + bottomEdge) / 2
        let avgHeight = (leftEdge + rightEdge) / 2
        guard avgWidth > 0, avgHeight > 0 else { return false }

        let ratio = min(avgWidth, avgHeight) / max(avgWidth, avgHeight)
        let center = isLandscape ? Self.portraitInBufferRatio : Self.targetAspectRatio
        let lower = center * (1 - Self.aspectRatioTolerance)
        let upper = center * (1 + Self.aspectRatioTolerance)
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
