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
    /// This method maps those coordinates to the video preview coordinate space.
    ///
    /// The key insight is that both photo and video come from the same camera. The video buffer is
    /// delivered in landscape orientation (1920x1080) but Vision processing treats it as the native
    /// sensor orientation. The preview layer handles the rotation for display.
    ///
    /// - Parameters:
    ///   - box: Bounding box in normalized coordinates from photo (top-left origin, 0-1 range)
    ///   - sourceSize: Size of the source photo image
    ///   - videoSize: Size of the video preview frame (landscape, e.g., 1920x1080)
    ///   - tolerance: Fractional margin around the reference rect
    static func calibrated(
        fromYOLO box: CGRect,
        sourceSize: CGSize,
        videoSize: CGSize,
        tolerance: CGFloat = 0.15
    ) -> DetectionZone {
        // The photo is captured in portrait orientation (e.g., 3024x4032)
        // The video is delivered in landscape orientation (1920x1080)
        //
        // Vision processes the video buffer in its native landscape orientation.
        // The preview layer rotates it for display.
        //
        // To map from photo coordinates to video/Vision coordinates:
        // We need to account for the 90-degree rotation between photo and video.
        //
        // Photo (portrait):     Video (landscape):
        // +----+----+----+      +----+----+----+----+----+----+----+
        // |    |    |    |      |    |    |    |    |    |    |    |
        // |    |CARD|    |      |    |    |    |CARD|    |    |    |
        // |    |    |    |      |    |    |    |    |    |    |    |
        // +----+----+----+      +----+----+----+----+----+----+----+
        //
        // The card appears in different positions due to rotation.
        // Photo X maps to Video Y (with flip), Photo Y maps to Video X.

        // For a direct mapping, we can use the fact that normalized coordinates
        // in the center region map approximately when accounting for aspect ratio difference.
        //
        // The video aspect ratio (16:9 = 1.78) is wider than photo (3:4 = 0.75).
        // When the video is displayed with resizeAspectFill on a portrait screen,
        // the video fills the height and crops the sides.
        //
        // For coordinate mapping:
        // - Photo X (0-1 left to right) -> maps to Video X' position
        // - Photo Y (0-1 top to bottom) -> maps to Video Y' position
        //
        // Since the video is landscape, when rotated for display:
        // - Photo left-right becomes display top-bottom (reversed)
        // - Photo top-bottom becomes display left-right

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
