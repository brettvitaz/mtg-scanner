import CoreGraphics

/// Stabilizes raw per-frame card detections using two techniques:
///
/// 1. **Identity matching** — each raw detection is matched to the nearest tracked
///    card (by IoU) so smoothing is applied per-card identity rather than per-slot.
///
/// 2. **EMA smoothing** — corner positions and bounding box are blended toward
///    new observations with `smoothingAlpha`. Lower alpha = smoother but laggier;
///    higher alpha = more responsive but jitterier. A value around 0.35 works well
///    for a stationary-card scanning use case.
///
/// 3. **Presence hysteresis** — a card must appear in `confirmFrames` consecutive
///    processed frames before its overlay becomes visible, and must be absent for
///    `dropFrames` consecutive frames before it is removed. This kills single-frame
///    phantom detections and prevents overlays from blinking when Vision briefly
///    misses a card.
///
/// Must be called from a single serial queue (visionQueue in CardDetectionEngine).
final class CardTracker {

    // MARK: - Configuration

    /// EMA blend factor: fraction of the new observation applied each frame.
    /// Range 0…1; 0.35 gives smooth motion with ~150ms of lag at 10 fps.
    var smoothingAlpha: CGFloat = 0.35

    /// Number of consecutive frames a new card must be detected before it is
    /// promoted to the visible set.
    var confirmFrames: Int = 3

    /// Number of consecutive frames a tracked card must be absent before it is
    /// removed from the visible set.
    var dropFrames: Int = 4

    // MARK: - Private State

    private var tracks: [Track] = []

    // MARK: - Public API

    /// Feed raw detections for one processed frame; returns the stable visible set.
    func update(detections: [DetectedCard]) -> [DetectedCard] {
        matchAndSmooth(detections: detections)
        pruneDropped()
        return tracks.filter { $0.isVisible }.map { $0.smoothed }
    }

    // MARK: - Private

    private func matchAndSmooth(detections: [DetectedCard]) {
        var unmatched = detections

        // For each existing track, find the best matching detection by IoU.
        for track in tracks {
            let best = unmatched.enumerated().max(by: {
                RectangleFilter.iou($0.element.boundingBox, track.smoothed.boundingBox) <
                RectangleFilter.iou($1.element.boundingBox, track.smoothed.boundingBox)
            })

            if let (idx, detection) = best,
               RectangleFilter.iou(detection.boundingBox, track.smoothed.boundingBox) > 0.25 {
                track.update(with: detection, alpha: smoothingAlpha)
                unmatched.remove(at: idx)
            } else {
                track.markMissed(dropFrames: dropFrames)
            }
        }

        // Any detections not matched to an existing track become new candidates.
        for detection in unmatched {
            tracks.append(Track(initial: detection, confirmFrames: confirmFrames))
        }
    }

    private func pruneDropped() {
        tracks.removeAll { $0.shouldRemove }
    }
}

// MARK: - Track

/// Internal per-card tracking state.
private final class Track {

    // MARK: State

    private(set) var smoothed: DetectedCard
    private var missedFrames: Int = 0
    private var confirmedFrames: Int
    private let confirmThreshold: Int

    var isVisible: Bool { confirmedFrames >= confirmThreshold && missedFrames == 0 }
    var shouldRemove: Bool { missedFrames > 0 && confirmedFrames < confirmThreshold }

    // MARK: Init

    init(initial: DetectedCard, confirmFrames: Int) {
        self.smoothed = initial
        self.confirmedFrames = 1
        self.confirmThreshold = confirmFrames
    }

    // MARK: Update

    func update(with detection: DetectedCard, alpha: CGFloat) {
        missedFrames = 0
        if confirmedFrames < confirmThreshold {
            confirmedFrames += 1
        }
        smoothed = blend(from: smoothed, to: detection, alpha: alpha)
    }

    func markMissed(dropFrames: Int) {
        missedFrames += 1
        if missedFrames > dropFrames {
            confirmedFrames = 0 // forces shouldRemove on next prune
        }
    }

    // MARK: EMA Blend

    private func blend(from old: DetectedCard, to new: DetectedCard, alpha: CGFloat) -> DetectedCard {
        DetectedCard(
            boundingBox: blendRect(old.boundingBox, new.boundingBox, alpha: alpha),
            topLeft:     blendPoint(old.topLeft,     new.topLeft,     alpha: alpha),
            topRight:    blendPoint(old.topRight,     new.topRight,    alpha: alpha),
            bottomRight: blendPoint(old.bottomRight,  new.bottomRight, alpha: alpha),
            bottomLeft:  blendPoint(old.bottomLeft,   new.bottomLeft,  alpha: alpha),
            confidence:  old.confidence * Float(1 - alpha) + new.confidence * Float(alpha),
            timestamp:   new.timestamp
        )
    }

    private func blendPoint(_ a: CGPoint, _ b: CGPoint, alpha: CGFloat) -> CGPoint {
        CGPoint(x: a.x * (1 - alpha) + b.x * alpha,
                y: a.y * (1 - alpha) + b.y * alpha)
    }

    private func blendRect(_ a: CGRect, _ b: CGRect, alpha: CGFloat) -> CGRect {
        CGRect(x:      a.minX   * (1 - alpha) + b.minX   * alpha,
               y:      a.minY   * (1 - alpha) + b.minY   * alpha,
               width:  a.width  * (1 - alpha) + b.width  * alpha,
               height: a.height * (1 - alpha) + b.height * alpha)
    }
}
