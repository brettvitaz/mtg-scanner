import CoreGraphics
import Vision

/// Filters and deduplicates `VNRectangleObservation` results for MTG card detection.
///
/// Responsibilities:
/// - Accept observations whose aspect ratio matches a standard MTG card (63mm × 88mm ≈ 0.716).
/// - Suppress overlapping detections using IoU-based Non-Maximum Suppression (NMS).
/// - Resolve nested rectangles differently for live scan detection and still-image crop generation.
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

    static let hintedCropMinAreaRatio: CGFloat = 0.60
    static let hintedCropMinHintCoverage: CGFloat = 0.45
    static let hintedCropMinCandidateCoverage: CGFloat = 0.50

    struct Configuration {
        let aspectRatioTolerance: CGFloat
        let enablesContainmentSuppression: Bool
        let prefersContainedSingleCard: Bool

        static let scan = Configuration(
            aspectRatioTolerance: RectangleFilter.scanAspectRatioTolerance,
            enablesContainmentSuppression: true,
            prefersContainedSingleCard: false
        )
        static let crop = Configuration(
            aspectRatioTolerance: RectangleFilter.cropAspectRatioTolerance,
            enablesContainmentSuppression: true,
            prefersContainedSingleCard: true
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
    /// 4. Suppresses nested boxes. Scan mode prefers enclosing single-card candidates; crop mode
    ///    prefers contained single-card candidates to avoid bin/table edges winning crop selection.
    /// 5. Re-sorts in top-left → bottom-right reading order.
    func filter(_ observations: [VNRectangleObservation], isLandscape: Bool) -> [VNRectangleObservation] {
        filterResult(observations, isLandscape: isLandscape).observations
    }

    func filterResult(_ observations: [VNRectangleObservation], isLandscape: Bool) -> FilterResult {
        let result = rankedResult(
            observations,
            isLandscape: isLandscape,
            visionHint: nil,
            preferSingle: false
        )
        return FilterResult(
            observations: result.observations,
            containmentSuppressionCount: result.containmentSuppressionCount
        )
    }

    /// Returns accepted observations ranked for still-image crop generation.
    ///
    /// `visionHint` is an optional normalized rectangle in Vision coordinates
    /// (bottom-left origin). When present, it biases ranking toward the rectangle
    /// that best overlaps the detector box without making the detector box the crop.
    func rank(
        _ observations: [VNRectangleObservation],
        isLandscape: Bool,
        visionHint: CGRect?,
        preferSingle: Bool
    ) -> [VNRectangleObservation] {
        rankedResult(
            observations,
            isLandscape: isLandscape,
            visionHint: visionHint,
            preferSingle: preferSingle
        ).observations
    }

    private func rankedResult(
        _ observations: [VNRectangleObservation],
        isLandscape: Bool,
        visionHint: CGRect?,
        preferSingle: Bool
    ) -> RankedResult {
        let candidates = observations
            .filter { $0.confidence >= Self.minConfidence }
            .filter { isCardAspectRatio($0, isLandscape: isLandscape) }
            .filter { isHintEligible($0, visionHint: visionHint, preferSingle: preferSingle) }
            .sorted {
                score($0, isLandscape: isLandscape, visionHint: visionHint) >
                    score($1, isLandscape: isLandscape, visionHint: visionHint)
            }

        let nmsAccepted = applyNMS(to: candidates)
        let containedSuppression = applyContainmentSuppression(to: nmsAccepted)
        var accepted = containedSuppression.observations

        if preferSingle {
            accepted.sort {
                score($0, isLandscape: isLandscape, visionHint: visionHint) >
                    score($1, isLandscape: isLandscape, visionHint: visionHint)
            }
            if visionHint == nil {
                accepted = Array(accepted.prefix(1))
            }
        } else {
            accepted.sort(by: Self.readingOrder)
        }

        return RankedResult(
            observations: accepted,
            containmentSuppressionCount: containedSuppression.suppressionCount
        )
    }
}

private extension RectangleFilter {
    private func applyNMS(to candidates: [VNRectangleObservation]) -> [VNRectangleObservation] {
        var accepted: [VNRectangleObservation] = []
        for obs in candidates {
            let isDuplicate = accepted.contains { Self.iou(obs.boundingBox, $0.boundingBox) > Self.iouThreshold }
            if !isDuplicate {
                accepted.append(obs)
            }
        }
        return accepted
    }

    private func applyContainmentSuppression(
        to observations: [VNRectangleObservation]
    ) -> ContainmentSuppressionResult {
        guard configuration.enablesContainmentSuppression else {
            return ContainmentSuppressionResult(observations: observations, suppressionCount: 0)
        }
        return suppressContainedObservations(observations)
    }

    // MARK: - Helpers

    static func readingOrder(_ a: VNRectangleObservation, _ b: VNRectangleObservation) -> Bool {
        let ay = a.boundingBox.maxY
        let by = b.boundingBox.maxY
        if abs(ay - by) > 0.05 { return ay > by }
        return a.boundingBox.minX < b.boundingBox.minX
    }

    private func score(_ obs: VNRectangleObservation, isLandscape: Bool, visionHint: CGRect?) -> CGFloat {
        let confidenceScore = CGFloat(obs.confidence)
        let aspectScore = aspectCloseness(obs, isLandscape: isLandscape)
        let areaScore = min(1, Self.area(of: obs.boundingBox) / 0.35)
        let hintScore = visionHint.map { hintSupportScore(obs.boundingBox, hint: $0) } ?? 0
        let hintWeight: CGFloat = visionHint == nil ? 0 : 0.35
        let baseWeight: CGFloat = 1 - hintWeight
        let areaWeight: CGFloat = configuration.prefersContainedSingleCard ? 0.03 : 0.10
        let confidenceWeight = 0.65 - areaWeight

        return baseWeight * (confidenceScore * confidenceWeight + aspectScore * 0.35 + areaScore * areaWeight)
            + hintScore * hintWeight
    }

    private func aspectCloseness(_ obs: VNRectangleObservation, isLandscape: Bool) -> CGFloat {
        guard let ratio = edgeAspectRatio(obs) else { return 0 }
        let center = isLandscape ? Self.portraitInBufferRatio : Self.targetAspectRatio
        let relativeError = abs(ratio - center) / center
        return max(0, 1 - relativeError / configuration.aspectRatioTolerance)
    }

    private func isCardAspectRatio(_ obs: VNRectangleObservation, isLandscape: Bool) -> Bool {
        guard let ratio = edgeAspectRatio(obs) else { return false }
        let center = isLandscape ? Self.portraitInBufferRatio : Self.targetAspectRatio
        let lower = center * (1 - configuration.aspectRatioTolerance)
        let upper = center * (1 + configuration.aspectRatioTolerance)
        return ratio >= lower && ratio <= upper
    }

    private func edgeAspectRatio(_ obs: VNRectangleObservation) -> CGFloat? {
        let topEdge = dist(obs.topLeft, obs.topRight)
        let bottomEdge = dist(obs.bottomLeft, obs.bottomRight)
        let leftEdge = dist(obs.topLeft, obs.bottomLeft)
        let rightEdge = dist(obs.topRight, obs.bottomRight)

        let avgWidth = (topEdge + bottomEdge) / 2
        let avgHeight = (leftEdge + rightEdge) / 2
        guard avgWidth > 0, avgHeight > 0 else { return nil }

        return min(avgWidth, avgHeight) / max(avgWidth, avgHeight)
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func hintSupportScore(_ rect: CGRect, hint: CGRect) -> CGFloat {
        let intersection = rect.intersection(hint)
        guard !intersection.isNull else { return 0 }
        let supportArea = Self.area(of: intersection)
        let largerArea = max(Self.area(of: rect), Self.area(of: hint))
        guard largerArea > 0 else { return 0 }
        return supportArea / largerArea
    }

    private func isHintEligible(
        _ obs: VNRectangleObservation,
        visionHint: CGRect?,
        preferSingle: Bool
    ) -> Bool {
        guard preferSingle, let visionHint else { return true }
        let rect = obs.boundingBox
        let rectArea = Self.area(of: rect)
        let hintArea = Self.area(of: visionHint)
        guard rectArea > 0, hintArea > 0 else { return false }

        let intersection = rect.intersection(visionHint)
        guard !intersection.isNull else { return false }
        let intersectionArea = Self.area(of: intersection)
        let areaRatio = rectArea / hintArea
        let hintCoverage = intersectionArea / hintArea
        let candidateCoverage = intersectionArea / rectArea

        return areaRatio >= Self.hintedCropMinAreaRatio &&
            hintCoverage >= Self.hintedCropMinHintCoverage &&
            candidateCoverage >= Self.hintedCropMinCandidateCoverage
    }

    private func suppressContainedObservations(
        _ observations: [VNRectangleObservation]
    ) -> ContainmentSuppressionResult {
        let containment = containmentGraph(for: observations)
        guard containment.contains(where: { !$0.isEmpty }) else {
            return ContainmentSuppressionResult(observations: observations, suppressionCount: 0)
        }

        let aggregateIndices = Set(observations.indices.filter { index in
            let childCount = directChildren(of: index, in: containment).count
            return configuration.prefersContainedSingleCard ? childCount >= 1 : childCount > 1
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
}

extension RectangleFilter {
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

    static func coverage(of rect: CGRect, by coveringRect: CGRect) -> CGFloat {
        let intersection = rect.intersection(coveringRect)
        guard !intersection.isNull else { return 0 }
        let rectArea = area(of: rect)
        guard rectArea > 0 else { return 0 }
        return area(of: intersection) / rectArea
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
    struct RankedResult {
        let observations: [VNRectangleObservation]
        let containmentSuppressionCount: Int
    }

    struct ContainmentSuppressionResult {
        let observations: [VNRectangleObservation]
        let suppressionCount: Int
    }
}
