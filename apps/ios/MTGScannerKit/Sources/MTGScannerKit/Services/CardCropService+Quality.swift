import CoreGraphics
import UIKit
import Vision

extension CardCropService {
    func qualityAcceptedCrops(
        from cgImage: CGImage,
        ranked: [VNRectangleObservation]
    ) -> [UIImage] {
        let evaluated = evaluatedCrops(from: cgImage, ranked: ranked)
        let accepted = evaluated.compactMap { result in
            result.quality.isUnderCrop || result.quality.isOverCrop ? nil : result.crop
        }
        if shouldKeepTwoCompleteCards(accepted: accepted, evaluated: evaluated) {
            return evaluated.map(\.crop)
        }
        if accepted.isEmpty, evaluated.count == ranked.count {
            return evaluated.map(\.crop)
        }
        return accepted
    }

    func mergedSplitCardCrop(
        from cgImage: CGImage,
        ranked: [VNRectangleObservation],
        sourceIsPortrait: Bool
    ) -> UIImage? {
        guard ranked.count == 2 else { return nil }
        let geometry = SplitCardGeometry(first: ranked[0].boundingBox, second: ranked[1].boundingBox)
        let crops = ranked.compactMap { cropCard(from: cgImage, observation: $0) }
        let traits = SplitCardTraits(geometry: geometry, crops: crops, sourceIsPortrait: sourceIsPortrait)
        guard traits.looksLikeSplitCard else { return nil }
        guard splitCandidatesAreAcceptable(traits: traits, crops: crops, rankedCount: ranked.count) else {
            return nil
        }
        guard let crop = axisAlignedVisionCrop(from: cgImage, visionBox: geometry.union) else { return nil }
        if traits.requiresMergedQualityCheck,
           !CropQualityEvaluator.evaluate(crop, maxHorizontalSkewDegrees: 1.50).passes {
            return nil
        }
        return crop
    }

    private func evaluatedCrops(
        from cgImage: CGImage,
        ranked: [VNRectangleObservation]
    ) -> [EvaluatedCrop] {
        ranked.compactMap { observation -> EvaluatedCrop? in
            guard let crop = cropCard(from: cgImage, observation: observation) else { return nil }
            let quality = CropQualityEvaluator.evaluate(
                crop,
                cropBox: observation.boundingBox,
                maxHorizontalSkewDegrees: 1.50
            )
            return EvaluatedCrop(crop: crop, quality: quality, boundingBox: observation.boundingBox)
        }
    }

    private func shouldKeepTwoCompleteCards(
        accepted: [UIImage],
        evaluated: [EvaluatedCrop]
    ) -> Bool {
        accepted.count == 1 &&
            evaluated.count == 2 &&
            evaluated.allSatisfy { !Self.touchesImageBounds($0.boundingBox) }
    }

    private func splitCandidatesAreAcceptable(
        traits: SplitCardTraits,
        crops: [UIImage],
        rankedCount: Int
    ) -> Bool {
        guard !traits.strongSignals else {
            return true
        }
        let results = crops.map { CropQualityEvaluator.evaluate($0, maxHorizontalSkewDegrees: 1.50) }
        return results.count == rankedCount && results.allSatisfy { !$0.passes }
    }

    private static func touchesImageBounds(_ box: CGRect) -> Bool {
        box.minX < 0.02 || box.minY < 0.02 || box.maxX > 0.98 || box.maxY > 0.98
    }
}

private struct EvaluatedCrop {
    let crop: UIImage
    let quality: CropQualityResult
    let boundingBox: CGRect
}

private struct SplitCardGeometry {
    let first: CGRect
    let second: CGRect
    let union: CGRect
    let aspectRatio: CGFloat
    let xOverlapRatio: CGFloat
    let yOverlapRatio: CGFloat
    let verticalGap: CGFloat
    let horizontalGap: CGFloat
    let centerDistance: CGFloat

    init(first: CGRect, second: CGRect) {
        self.first = first
        self.second = second
        union = first.union(second)
        aspectRatio = min(union.width, union.height) / max(union.width, union.height)
        xOverlapRatio = Self.overlapRatio(first.minX...first.maxX, second.minX...second.maxX)
        yOverlapRatio = Self.overlapRatio(first.minY...first.maxY, second.minY...second.maxY)
        verticalGap = max(first.minY, second.minY) - min(first.maxY, second.maxY)
        horizontalGap = max(first.minX, second.minX) - min(first.maxX, second.maxX)
        centerDistance = hypot(first.midX - second.midX, first.midY - second.midY)
    }

    private static func overlapRatio(_ first: ClosedRange<CGFloat>, _ second: ClosedRange<CGFloat>) -> CGFloat {
        let overlap = min(first.upperBound, second.upperBound) - max(first.lowerBound, second.lowerBound)
        let width = min(first.upperBound - first.lowerBound, second.upperBound - second.lowerBound)
        return width > 0 ? max(0, overlap) / width : 0
    }
}

private struct SplitCardTraits {
    let geometry: SplitCardGeometry
    let landscapeHalves: Bool
    let compactUnevenHalves: Bool
    let sourceIsPortrait: Bool

    init(geometry: SplitCardGeometry, crops: [UIImage], sourceIsPortrait: Bool) {
        self.geometry = geometry
        self.sourceIsPortrait = sourceIsPortrait
        landscapeHalves = crops.allSatisfy { $0.size.width > $0.size.height }
        compactUnevenHalves = Self.compactUnevenHalves(crops)
    }

    var looksLikeSplitCard: Bool {
        strongSignals || weakGeometrySignal
    }

    var strongSignals: Bool {
        sourceIsPortrait || geometry.centerDistance < 0.35 || landscapeHalves || compactUnevenHalves
    }

    var requiresMergedQualityCheck: Bool {
        geometry.xOverlapRatio > 0.75 && !strongSignals
    }

    private var weakGeometrySignal: Bool {
        let verticallySplit = geometry.xOverlapRatio > 0.75 && geometry.verticalGap < 0.08
        let horizontallySplit = geometry.yOverlapRatio > 0.75 && geometry.horizontalGap < 0.03
        return (verticallySplit || horizontallySplit) &&
            abs(geometry.aspectRatio - RectangleFilter.targetAspectRatio) < 0.18
    }

    private static func compactUnevenHalves(_ crops: [UIImage]) -> Bool {
        guard crops.count == 2 else { return false }
        let widthRatio = min(crops[0].size.width, crops[1].size.width) /
            max(crops[0].size.width, crops[1].size.width)
        return max(crops[0].size.width, crops[1].size.width) < 600 && widthRatio < 0.90
    }
}
