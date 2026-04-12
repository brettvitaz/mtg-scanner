import CoreGraphics
import Vision

enum ScanYOLOSupport {
    static let iouThreshold: CGFloat = 0.35
    static let coverageThreshold: CGFloat = 0.60
    static let looseCoverageAreaRatioThreshold: CGFloat = 1.8

    static func validate(
        _ observations: [VNRectangleObservation],
        with yoloBoxes: [CGRect]?
    ) -> ValidationResult {
        guard !observations.isEmpty else {
            return ValidationResult(observations: [], yoloAcceptedCount: 0, yoloRejectedCount: 0, usedFallback: false)
        }
        guard let yoloBoxes else {
            return ValidationResult(
                observations: observations, yoloAcceptedCount: 0, yoloRejectedCount: 0, usedFallback: true
            )
        }
        guard !yoloBoxes.isEmpty else {
            return ValidationResult(
                observations: observations, yoloAcceptedCount: 0, yoloRejectedCount: 0, usedFallback: true
            )
        }

        let supportScores = observations.map { bestSupportScore(for: $0.boundingBox, in: yoloBoxes) }
        let directlyAcceptedCount = supportScores.filter { $0 >= coverageThreshold }.count
        let rejectedIDs = nestedRejectionIDs(observations: observations, supportScores: supportScores)
        let accepted = observations.filter { !rejectedIDs.contains(ObjectIdentifier($0)) }

        return ValidationResult(
            observations: accepted,
            yoloAcceptedCount: directlyAcceptedCount,
            yoloRejectedCount: rejectedIDs.count,
            usedFallback: false
        )
    }

    static func supports(rectangle: CGRect, with yoloBoxes: [CGRect]) -> Bool {
        yoloBoxes.contains { supports(rectangle: rectangle, with: $0) }
    }

    static func visionBox(from yoloBox: CGRect) -> CGRect {
        CGRect(x: yoloBox.minX, y: 1.0 - yoloBox.maxY, width: yoloBox.width, height: yoloBox.height)
    }

    static func coverage(of rect: CGRect, by coveringRect: CGRect) -> CGFloat {
        let intersection = rect.intersection(coveringRect)
        guard !intersection.isNull else { return 0 }
        let rectArea = RectangleFilter.area(of: rect)
        guard rectArea > 0 else { return 0 }
        return RectangleFilter.area(of: intersection) / rectArea
    }

    private static func bestSupportScore(for rectangle: CGRect, in yoloBoxes: [CGRect]) -> CGFloat {
        yoloBoxes.reduce(0) { bestScore, yoloBox in
            max(bestScore, supportScore(rectangle: rectangle, with: yoloBox))
        }
    }

    private static func supportScore(rectangle: CGRect, with yoloBox: CGRect) -> CGFloat {
        let iou = RectangleFilter.iou(rectangle, yoloBox)
        let areaRatio = largerToSmallerAreaRatio(between: rectangle, and: yoloBox)
        let yoloCoveredByRectangle = coverage(of: yoloBox, by: rectangle)
        let rectangleCoveredByYOLO = coverage(of: rectangle, by: yoloBox)
        let enclosureCoverage = yoloCoveredByRectangle >= coverageThreshold
            && areaRatio <= looseCoverageAreaRatioThreshold
        let looseCoverage = rectangleCoveredByYOLO >= coverageThreshold
            && areaRatio <= looseCoverageAreaRatioThreshold
        return max(
            iou,
            enclosureCoverage ? yoloCoveredByRectangle : 0,
            looseCoverage ? rectangleCoveredByYOLO : 0
        )
    }

    private static func supports(rectangle: CGRect, with yoloBox: CGRect) -> Bool {
        supportScore(rectangle: rectangle, with: yoloBox) >= coverageThreshold
    }

    private static func nestedRejectionIDs(
        observations: [VNRectangleObservation],
        supportScores: [CGFloat]
    ) -> Set<ObjectIdentifier> {
        var rejectedIDs: Set<ObjectIdentifier> = []
        for (candidateIndex, candidate) in observations.enumerated() {
            let candidateBox = candidate.boundingBox
            let candidateArea = RectangleFilter.area(of: candidateBox)
            guard candidateArea > 0 else { continue }
            guard supportScores[candidateIndex] < coverageThreshold else { continue }

            let shouldReject = observations.enumerated().contains { index, supported in
                guard index != candidateIndex else { return false }
                let supportedBox = supported.boundingBox
                let supportedArea = RectangleFilter.area(of: supportedBox)
                guard supportedArea / candidateArea >= RectangleFilter.containmentAreaRatioThreshold else {
                    return false
                }
                guard supportScores[index] >= coverageThreshold else { return false }
                return RectangleFilter.containmentRatio(of: candidateBox, in: supportedBox) >=
                    RectangleFilter.containmentThreshold
            }

            if shouldReject {
                rejectedIDs.insert(ObjectIdentifier(candidate))
            }
        }
        return rejectedIDs
    }

    private static func largerToSmallerAreaRatio(between a: CGRect, and b: CGRect) -> CGFloat {
        let aArea = RectangleFilter.area(of: a)
        let bArea = RectangleFilter.area(of: b)
        guard aArea > 0, bArea > 0 else { return .infinity }
        return max(aArea, bArea) / min(aArea, bArea)
    }

    struct ValidationResult {
        let observations: [VNRectangleObservation]
        let yoloAcceptedCount: Int
        let yoloRejectedCount: Int
        let usedFallback: Bool
    }
}

// MARK: - CardDetectionEngine YOLO state types

extension CardDetectionEngine {
    struct ScanYOLOValidationState {
        static let validationStride = 3
        static let cacheTTL: TimeInterval = 0.25

        var boxes: [CGRect] = []
        var lastTimestamp: TimeInterval?
        var frameCounter = 0
        var hasCachedBoxes = false
        var refreshInFlight = false
        var generation = 0

        mutating func boxesForFrame(timestamp: TimeInterval) -> ScanYOLORefreshDecision {
            frameCounter += 1
            let cacheIsFresh: Bool
            if let lastTimestamp {
                cacheIsFresh = (timestamp - lastTimestamp) <= Self.cacheTTL
            } else {
                cacheIsFresh = false
            }
            let shouldRefresh = !hasCachedBoxes || !cacheIsFresh || frameCounter % Self.validationStride == 0
            let shouldStartRefresh = shouldRefresh && !refreshInFlight
            if shouldStartRefresh { refreshInFlight = true }
            return ScanYOLORefreshDecision(
                cachedBoxes: hasCachedBoxes ? boxes : nil,
                shouldStartRefresh: shouldStartRefresh,
                generation: generation
            )
        }

        mutating func storeRefresh(boxes: [CGRect], timestamp: TimeInterval, generation: Int) {
            guard generation == self.generation else { return }
            self.boxes = boxes
            lastTimestamp = timestamp
            hasCachedBoxes = true
            refreshInFlight = false
        }

        mutating func finishRefreshWithoutResult() { refreshInFlight = false }

        mutating func reset() {
            boxes = []
            lastTimestamp = nil
            frameCounter = 0
            hasCachedBoxes = false
            refreshInFlight = false
            generation += 1
        }
    }

    struct ScanYOLORefreshDecision {
        let cachedBoxes: [CGRect]?
        let shouldStartRefresh: Bool
        let generation: Int
    }

    struct ScanYOLOValidationResult {
        let observations: [VNRectangleObservation]
        let yoloBoxes: [CGRect]
        let yoloAcceptedCount: Int
        let yoloRejectedCount: Int
        let usedFallback: Bool
    }
}
