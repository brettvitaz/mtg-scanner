import XCTest
import Vision
@testable import MTGScannerKit

final class RectangleFilterNMSTests: XCTestCase {

    private let filter = RectangleFilter()
    private let cropFilter = RectangleFilter(configuration: .crop)

    // MARK: - NMS

    func testFilterSuppressesHeavilyOverlappingDuplicates() {
        let ratio = RectangleFilter.targetAspectRatio
        let height: CGFloat = 0.4
        let width = height * ratio
        let high = makeObservation(box: CGRect(x: 0.1, y: 0.1, width: width, height: height), confidence: 0.9)
        let low = makeObservation(box: CGRect(x: 0.102, y: 0.102, width: width, height: height), confidence: 0.6)
        let result = filter.filter([low, high], isLandscape: false)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].confidence, 0.9, accuracy: 0.001)
    }

    func testFilterPreservesNonOverlappingDetections() {
        let ratio = RectangleFilter.targetAspectRatio
        let height: CGFloat = 0.3
        let width = height * ratio
        let left = makeObservation(box: CGRect(x: 0.0, y: 0.1, width: width, height: height), confidence: 0.8)
        let right = makeObservation(box: CGRect(x: 0.6, y: 0.1, width: width, height: height), confidence: 0.7)
        let result = filter.filter([left, right], isLandscape: false)
        XCTAssertEqual(result.count, 2)
    }

    func testFilterPrefersEnclosingCardOverHigherConfidenceInnerFeature() {
        let ratio = RectangleFilter.targetAspectRatio
        let outer = makeObservation(box: CGRect(x: 0.10, y: 0.10, width: 0.45 * ratio, height: 0.45), confidence: 0.75)
        let inner = makeObservation(box: CGRect(x: 0.16, y: 0.18, width: 0.22 * ratio, height: 0.22), confidence: 0.95)
        let result = filter.filter([inner, outer], isLandscape: false)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].boundingBox, outer.boundingBox)
    }

    func testFilterPrefersEnclosingCardOverHigherConfidenceInnerFeatureRegardlessOfInputOrder() {
        let ratio = RectangleFilter.targetAspectRatio
        let outer = makeObservation(box: CGRect(x: 0.10, y: 0.10, width: 0.45 * ratio, height: 0.45), confidence: 0.75)
        let inner = makeObservation(box: CGRect(x: 0.16, y: 0.18, width: 0.22 * ratio, height: 0.22), confidence: 0.95)
        let result = filter.filter([outer, inner], isLandscape: false)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].boundingBox, outer.boundingBox)
    }

    func testFilterSuppressesNestedInnerFeatureWhenOuterCardIsAcceptedFirst() {
        let ratio = RectangleFilter.targetAspectRatio
        let outer = makeObservation(box: CGRect(x: 0.10, y: 0.10, width: 0.45 * ratio, height: 0.45), confidence: 0.95)
        let inner = makeObservation(box: CGRect(x: 0.16, y: 0.18, width: 0.22 * ratio, height: 0.22), confidence: 0.75)
        let result = filter.filter([outer, inner], isLandscape: false)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].boundingBox, outer.boundingBox)
    }

    func testFilterKeepsHigherConfidenceInnerCardWhenOuterBoxIsOnlySlightlyLarger() {
        let ratio = RectangleFilter.targetAspectRatio
        let inner = makeObservation(
            box: CGRect(x: 0.12, y: 0.12, width: 0.40 * ratio, height: 0.40), confidence: 0.95)
        let outer = makeObservation(
            box: CGRect(x: 0.105, y: 0.105, width: 0.43 * ratio, height: 0.43), confidence: 0.45)
        let result = filter.filter([inner, outer], isLandscape: false)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].boundingBox, inner.boundingBox)
    }

    func testFilterDoesNotReplaceMultipleContainedInnerBoxesWithSingleOuterBox() {
        let ratio = RectangleFilter.targetAspectRatio
        let leftInner = makeObservation(
            box: CGRect(x: 0.14, y: 0.16, width: 0.22 * ratio, height: 0.22), confidence: 0.95)
        let rightInner = makeObservation(
            box: CGRect(x: 0.30, y: 0.18, width: 0.22 * ratio, height: 0.22), confidence: 0.90)
        let outer = makeObservation(box: CGRect(x: 0.10, y: 0.10, width: 0.50 * ratio, height: 0.50), confidence: 0.70)
        let result = filter.filter([leftInner, rightInner, outer], isLandscape: false)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].boundingBox, leftInner.boundingBox)
        XCTAssertEqual(result[1].boundingBox, rightInner.boundingBox)
    }

    func testFilterKeepsOutermostSingleCardAcrossContainmentChain() {
        let ratio = RectangleFilter.targetAspectRatio
        let outer = makeObservation(box: CGRect(x: 0.08, y: 0.08, width: 0.52 * ratio, height: 0.52), confidence: 0.70)
        let middle = makeObservation(box: CGRect(x: 0.14, y: 0.16, width: 0.34 * ratio, height: 0.34), confidence: 0.85)
        let inner = makeObservation(box: CGRect(x: 0.20, y: 0.24, width: 0.20 * ratio, height: 0.20), confidence: 0.95)
        let result = filter.filter([inner, middle, outer], isLandscape: false)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].boundingBox, outer.boundingBox)
    }

    func testFilterKeepsPartiallyOverlappingBoxesBelowContainmentThreshold() {
        let ratio = RectangleFilter.targetAspectRatio
        let height: CGFloat = 0.32
        let width = height * ratio
        let first = makeObservation(box: CGRect(x: 0.10, y: 0.10, width: width, height: height), confidence: 0.90)
        let second = makeObservation(box: CGRect(x: 0.22, y: 0.18, width: width, height: height), confidence: 0.85)
        let result = filter.filter([first, second], isLandscape: false)
        XCTAssertEqual(result.count, 2)
    }

    func testFilterKeepsAlmostSameSizeBoxesForNMSInsteadOfContainment() {
        let ratio = RectangleFilter.targetAspectRatio
        let outerHeight: CGFloat = 0.40
        let innerHeight = outerHeight / sqrt(RectangleFilter.containmentAreaRatioThreshold - 0.05)
        let larger = makeObservation(
            box: CGRect(x: 0.10, y: 0.10, width: outerHeight * ratio, height: outerHeight), confidence: 0.90)
        let almostSame = makeObservation(
            box: CGRect(x: 0.105, y: 0.105, width: innerHeight * ratio, height: innerHeight), confidence: 0.80)
        let result = filter.filter([larger, almostSame], isLandscape: false)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].boundingBox, larger.boundingBox)
    }

    func testCropFilterDoesNotApplyContainmentSuppression() {
        let ratio = RectangleFilter.targetAspectRatio
        let outer = makeObservation(box: CGRect(x: 0.10, y: 0.10, width: 0.45 * ratio, height: 0.45), confidence: 0.75)
        let inner = makeObservation(box: CGRect(x: 0.16, y: 0.18, width: 0.22 * ratio, height: 0.22), confidence: 0.95)
        let result = cropFilter.filter([inner, outer], isLandscape: false)
        XCTAssertEqual(result.count, 2)
    }

    func testFilterReturnsEmptyForEmptyInput() {
        XCTAssertEqual(filter.filter([], isLandscape: false).count, 0)
    }

    // MARK: - Spatial sort

    func testSpatialSortComparatorOrdersLowerMinYFirst() {
        let boxes: [CGRect] = [
            CGRect(x: 0.1, y: 0.70, width: 0.18, height: 0.25),
            CGRect(x: 0.1, y: 0.05, width: 0.18, height: 0.25),
            CGRect(x: 0.5, y: 0.05, width: 0.18, height: 0.25)
        ]
        let sorted = boxes.sorted { a, b in
            let ay = a.minY
            let by = b.minY
            if abs(ay - by) > 0.05 { return ay < by }
            return a.minX < b.minX
        }
        XCTAssertEqual(sorted[0].minY, 0.05, accuracy: 0.001)
        XCTAssertEqual(sorted[0].minX, 0.1, accuracy: 0.001)
        XCTAssertEqual(sorted[1].minY, 0.05, accuracy: 0.001)
        XCTAssertEqual(sorted[1].minX, 0.5, accuracy: 0.001)
        XCTAssertEqual(sorted[2].minY, 0.70, accuracy: 0.001)
    }

    // MARK: - Helpers

    private func makeObservation(box: CGRect, confidence: Float) -> VNRectangleObservation {
        makeRectangleObservation(box: box, confidence: confidence)
    }
}
