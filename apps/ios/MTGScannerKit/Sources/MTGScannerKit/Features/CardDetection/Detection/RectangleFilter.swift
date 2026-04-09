import CoreGraphics
import Vision

/// Filters and deduplicates `VNRectangleObservation` results for MTG card detection.
///
/// Responsibilities:
/// - Accept observations whose aspect ratio matches a standard MTG card (63mm × 88mm ≈ 0.716).
/// - Suppress overlapping detections using IoU-based Non-Maximum Suppression (NMS).
/// - Prefer enclosing single-card rectangles over nested feature boxes while preserving peers.
/// - Re-sort accepted observations in reading order (top-left to bottom-right).
struct RectangleFilter {

    // MARK: - Constants

    /// Standard MTG card portrait aspect ratio (short side / long side = 63 / 88 ≈ 0.714).
    static let targetAspectRatio: CGFloat = 63.0 / 88.0

    /// Relative tolerance used by the stricter crop-generation path.
    static let cropAspectRatioTolerance: CGFloat = 0.20

    /// Relative tolerance used by live scan mode where perspective distortion is more common.
    static let scanAspectRatioTolerance: CGFloat = 0.30

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

    /// Minimum fraction of the smaller box that must be covered by the larger box to count as
    /// a contained false positive.
    static let containmentThreshold: CGFloat = 0.90

    /// Minimum larger/smaller area ratio required before containment suppression fires.
    static let containmentAreaRatioThreshold: CGFloat = 1.50

    struct Configuration {
        let aspectRatioTolerance: CGFloat
        let enablesContainmentSuppression: Bool

        static let scan = Configuration(
            aspectRatioTolerance: RectangleFilter.scanAspectRatioTolerance,
            enablesContainmentSuppression: true
        )
        static let crop = Configuration(
            aspectRatioTolerance: RectangleFilter.cropAspectRatioTolerance,
            enablesContainmentSuppression: false
        )
    }

    let configuration: Configuration

    init(configuration: Configuration = .scan) {
        self.configuration = configuration
    }

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
    /// 4. Suppresses nested inner boxes by preferring the enclosing single-card candidate and
    ///    discarding aggregate outer boxes that merely contain multiple peer cards.
    /// 5. Re-sorts in top-left → bottom-right reading order.
    func filter(_ observations: [VNRectangleObservation], isLandscape: Bool) -> [VNRectangleObservation] {
        filterResult(observations, isLandscape: isLandscape).observations
    }

    func filterResult(_ observations: [VNRectangleObservation], isLandscape: Bool) -> FilterResult {
        let candidates = observations
            .filter { $0.confidence >= Self.minConfidence }
            .filter { isCardAspectRatio($0, isLandscape: isLandscape) }
            .sorted { $0.confidence > $1.confidence }

        var nmsAccepted: [VNRectangleObservation] = []
        for obs in candidates {
            let isDuplicate = nmsAccepted.contains { Self.iou(obs.boundingBox, $0.boundingBox) > Self.iouThreshold }
            if !isDuplicate {
                nmsAccepted.append(obs)
            }
        }

        let containedSuppression: ContainmentSuppressionResult
        if configuration.enablesContainmentSuppression {
            containedSuppression = suppressContainedObservations(nmsAccepted)
        } else {
            containedSuppression = ContainmentSuppressionResult(
                observations: nmsAccepted,
                suppressionCount: 0
            )
        }
        var accepted = containedSuppression.observations

        accepted.sort { a, b in
            let ay = a.boundingBox.minY
            let by = b.boundingBox.minY
            if abs(ay - by) > 0.05 { return ay < by }
            return a.boundingBox.minX < b.boundingBox.minX
        }

        return FilterResult(
            observations: accepted,
            containmentSuppressionCount: containedSuppression.suppressionCount
        )
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
        let lower = center * (1 - configuration.aspectRatioTolerance)
        let upper = center * (1 + configuration.aspectRatioTolerance)
        return ratio >= lower && ratio <= upper
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func suppressContainedObservations(
        _ observations: [VNRectangleObservation]
    ) -> ContainmentSuppressionResult {
        let containment = containmentGraph(for: observations)
        guard containment.contains(where: { !$0.isEmpty }) else {
            return ContainmentSuppressionResult(observations: observations, suppressionCount: 0)
        }

        let aggregateIndices = Set(observations.indices.filter {
            directChildren(of: $0, in: containment).count > 1
        })
        let suppressedIndices = Set(observations.indices.filter { index in
            if aggregateIndices.contains(index) {
                return true
            }

            return observations.indices.contains { ancestor in
                guard ancestor != index else { return false }
                guard !aggregateIndices.contains(ancestor) else { return false }
                return containment[ancestor].contains(index)
            }
        })

        let kept = observations.enumerated().compactMap { index, observation in
            suppressedIndices.contains(index) ? nil : observation
        }

        return ContainmentSuppressionResult(
            observations: kept,
            suppressionCount: suppressedIndices.count
        )
    }

    private func containmentGraph(for observations: [VNRectangleObservation]) -> [Set<Int>] {
        observations.indices.map { outerIndex in
            Set(observations.indices.filter { innerIndex in
                outerIndex != innerIndex
                    && Self.substantiallyContains(
                        observations[outerIndex].boundingBox,
                        observations[innerIndex].boundingBox
                    )
            })
        }
    }

    private func directChildren(of parentIndex: Int, in containment: [Set<Int>]) -> [Int] {
        containment[parentIndex].filter { childIndex in
            !containment[parentIndex].contains { intermediateIndex in
                intermediateIndex != childIndex
                    && containment[intermediateIndex].contains(childIndex)
            }
        }
    }

    private static func substantiallyContains(_ outer: CGRect, _ inner: CGRect) -> Bool {
        let outerArea = area(of: outer)
        let innerArea = area(of: inner)
        guard outerArea > 0, innerArea > 0 else { return false }
        guard outerArea / innerArea >= containmentAreaRatioThreshold else { return false }
        return containmentRatio(of: inner, in: outer) >= containmentThreshold
    }

    /// Intersection-over-union of two axis-aligned rectangles in normalized coordinates.
    static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let ix = max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX))
        let iy = max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
        let intersection = ix * iy
        let union = a.width * a.height + b.width * b.height - intersection
        return union > 0 ? intersection / union : 0
    }

    static func containmentRatio(of inner: CGRect, in outer: CGRect) -> CGFloat {
        let intersection = inner.intersection(outer)
        guard !intersection.isNull else { return 0 }
        let innerArea = area(of: inner)
        guard innerArea > 0 else { return 0 }
        return area(of: intersection) / innerArea
    }

    static func area(of rect: CGRect) -> CGFloat {
        rect.width * rect.height
    }
}

extension RectangleFilter {
    struct FilterResult {
        let observations: [VNRectangleObservation]
        let containmentSuppressionCount: Int
    }
}

private extension RectangleFilter {
    struct ContainmentSuppressionResult {
        let observations: [VNRectangleObservation]
        let suppressionCount: Int
    }
}
