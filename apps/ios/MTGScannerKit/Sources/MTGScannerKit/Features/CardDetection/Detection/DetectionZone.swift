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
struct DetectionZone: Sendable, Equatable {
    /// Default detection zone covering the full frame with standard tolerance.
    static let fullFrame = DetectionZone(
        referenceRect: CGRect(x: 0, y: 0, width: 1, height: 1),
        tolerance: 0
    )

    /// Default zone for uncalibrated state (before first capture).
    ///
    /// Covers the center 80% of the frame (10% inset on each edge), rejecting
    /// extreme-edge detections while remaining generous for varied mounting setups.
    /// Only enforces portrait aspect ratio — size is not constrained because the
    /// correct card size is unknown until calibration.
    static var uncalibrated: DetectionZone {
        var zone = DetectionZone(
            referenceRect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
            tolerance: 0
        )
        zone.minAreaFraction = 0
        return zone
    }

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

    /// Radius (in normalized coordinates) for center-proximity acceptance.
    ///
    /// Derived from the reference rect's half-span plus tolerance, so the
    /// allowed-center region tracks the calibration tightness automatically.
    var centerProximityRadius: CGFloat {
        let halfSpan = max(referenceRect.width, referenceRect.height) / 2
        return halfSpan * (1 + tolerance)
    }

    /// Returns true if the box's center lies within `centerProximityRadius` of the zone's center.
    ///
    /// Used instead of full containment so cards that grow larger in the frame
    /// (e.g. a growing physical stack) still pass the filter as long as they remain
    /// centered in the calibrated area.
    func containsCenter(of box: CGRect) -> Bool {
        let dx = box.midX - center.x
        let dy = box.midY - center.y
        let r = centerProximityRadius
        return (dx * dx + dy * dy) <= (r * r)
    }

    /// Creates a new zone calibrated from a detected card bounding box.
    ///
    /// The box is expected to be in Vision coordinates (bottom-left origin).
    /// The tolerance provides flexibility for cards that are slightly offset from center.
    /// Size filtering is disabled (minAreaFraction = 0) because the card size in the frame
    /// varies with camera distance — containment and aspect ratio are the meaningful filters.
    static func calibrated(from box: CGRect, tolerance: CGFloat = 0.15) -> DetectionZone {
        var zone = DetectionZone(referenceRect: box, tolerance: tolerance)
        zone.minAreaFraction = 0
        return zone
    }

    /// Creates a new zone calibrated from a YOLO bounding box in normalized coordinates.
    ///
    /// YOLOCardDetector returns boxes in normalized coordinates (0-1, top-left origin) from the captured photo.
    /// This method maps those coordinates to the video preview coordinate space via 90° rotation.
    ///
    /// Both photo and video come from the same camera. The photo is portrait; the video buffer is landscape.
    /// Normalized coordinates map through rotation: photo X → video Y, photo Y → 1 - video X.
    /// The preview layer handles display rotation for all device orientations.
    ///
    /// - Parameters:
    ///   - box: Bounding box in normalized coordinates from photo (top-left origin, 0-1 range)
    ///   - tolerance: Fractional margin around the reference rect
    static func calibrated(
        fromYOLO box: CGRect,
        tolerance: CGFloat = 0.15
    ) -> DetectionZone {
        // Calculate the center point of the box
        let centerX = box.midX
        let centerY = box.midY

        // Map from photo portrait to video landscape coordinates
        // Photo center X (left-right) -> Video Y position (accounting for rotation)
        // Photo center Y (top-bottom) -> Video X position
        //
        // With 90-degree rotation: X' = Y, Y' = 1-X
        let videoNormX = centerY
        let videoNormY = 1.0 - centerX

        // Width and height also swap with rotation
        let videoWidth = box.height
        let videoHeight = box.width

        // Calculate the box in video normalized coordinates (top-left origin)
        let videoBox = CGRect(
            x: videoNormX - videoWidth / 2,
            y: videoNormY - videoHeight / 2,
            width: videoWidth,
            height: videoHeight
        )

        // Convert to Vision coordinates (bottom-left origin)
        let visionRect = CGRect(
            x: videoBox.minX,
            y: 1.0 - videoBox.maxY,
            width: videoBox.width,
            height: videoBox.height
        )

        var zone = DetectionZone(referenceRect: visionRect, tolerance: tolerance)
        zone.minAreaFraction = 0
        return zone
    }

}
