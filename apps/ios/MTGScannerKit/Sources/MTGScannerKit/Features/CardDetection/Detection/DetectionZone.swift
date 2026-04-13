import CoreGraphics

/// Defines the acceptable region and constraints for card detection in auto-scan mode.
///
/// Coordinates are normalized (0-1) with bottom-left origin, matching Vision/VNDetectRectanglesRequest.
/// Use `calibrated(fromYOLO:)` to create from YOLOCardDetector output which uses top-left origin.
///
/// The zone enforces three constraints:
/// 1. **Containment** — cards must be fully within the zone (with tolerance margin)
/// 2. **Size** — cards must cover at least `minAreaFraction` of the frame
/// 3. **Aspect ratio** — cards must be in portrait orientation
struct DetectionZone: Sendable {
    /// Default detection zone covering the full frame with standard tolerance.
    static let fullFrame = DetectionZone(
        referenceRect: CGRect(x: 0, y: 0, width: 1, height: 1),
        tolerance: 0
    )

    /// Normalized rectangle defining the center of the detection zone.
    /// Must be in Vision coordinates (bottom-left origin).
    var referenceRect: CGRect

    /// Fractional margin around the reference rect to expand the detection area.
    /// Applied equally to all edges.
    var tolerance: CGFloat

    /// Minimum fraction of the frame area a card must cover to be accepted.
    var minAreaFraction: CGFloat = 0.40

    /// Maximum aspect ratio (width/height) for portrait orientation acceptance.
    var maxPortraitAspectRatio: CGFloat = 0.8

    init(referenceRect: CGRect, tolerance: CGFloat = 0.15) {
        self.referenceRect = referenceRect
        self.tolerance = tolerance
    }

    /// Returns the effective detection area by expanding the reference rect by tolerance.
    var effectiveRect: CGRect {
        let dx = referenceRect.width * tolerance
        let dy = referenceRect.height * tolerance
        return referenceRect.insetBy(dx: -dx, dy: -dy)
    }

    /// Checks if a bounding box is fully contained within the effective zone.
    ///
    /// The box must be entirely inside the zone (no edge may extend outside).
    func contains(_ box: CGRect) -> Bool {
        effectiveRect.contains(box)
    }

    /// Checks if a bounding box meets the minimum area threshold.
    ///
    /// The box area must be at least `minAreaFraction` of the frame area (1.0).
    func isLargeEnough(_ box: CGRect) -> Bool {
        box.width * box.height >= minAreaFraction
    }

    /// Checks if a bounding box has acceptable portrait aspect ratio.
    ///
    /// Returns true if width/height is less than `maxPortraitAspectRatio`
    /// (i.e., taller than wide).
    func isPortraitAspect(_ box: CGRect) -> Bool {
        guard box.height > 0 else { return false }
        return box.width / box.height <= maxPortraitAspectRatio
    }

    /// Returns the centroid of the reference rectangle.
    var center: CGPoint {
        CGPoint(x: referenceRect.midX, y: referenceRect.midY)
    }

    /// Creates a new zone calibrated from a detected card bounding box.
    ///
    /// The box is expected to be in Vision coordinates (bottom-left origin).
    /// The tolerance provides flexibility for cards that are slightly offset from center.
    static func calibrated(from box: CGRect, tolerance: CGFloat = 0.15) -> DetectionZone {
        DetectionZone(referenceRect: box, tolerance: tolerance)
    }

    /// Creates a new zone calibrated from a YOLO bounding box.
    ///
    /// YOLOCardDetector uses top-left origin coordinates, so this converts
    /// to Vision bottom-left coordinates before storing.
    static func calibrated(fromYOLO box: CGRect, tolerance: CGFloat = 0.15) -> DetectionZone {
        let visionRect = CGRect(
            x: box.minX,
            y: 1.0 - box.maxY,
            width: box.width,
            height: box.height
        )
        return DetectionZone(referenceRect: visionRect, tolerance: tolerance)
    }
}
