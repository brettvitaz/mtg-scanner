import XCTest
import Vision
@testable import MTGScannerKit

final class ScanYOLOSupportTests: XCTestCase {

    func testVisionBoxConvertsTopLeftOriginToBottomLeftOrigin() {
        let yoloBox = CGRect(x: 0.2, y: 0.1, width: 0.3, height: 0.4)

        let visionBox = ScanYOLOSupport.visionBox(from: yoloBox)

        XCTAssertEqual(visionBox.minX, 0.2, accuracy: 0.001)
        XCTAssertEqual(visionBox.minY, 0.5, accuracy: 0.001)
        XCTAssertEqual(visionBox.width, 0.3, accuracy: 0.001)
        XCTAssertEqual(visionBox.height, 0.4, accuracy: 0.001)
    }

    func testSupportsRectangleWhenIoUExceedsThreshold() {
        let rectangle = CGRect(x: 0.10, y: 0.10, width: 0.20, height: 0.30)
        let yoloBox = CGRect(x: 0.11, y: 0.11, width: 0.21, height: 0.31)

        XCTAssertTrue(ScanYOLOSupport.supports(rectangle: rectangle, with: [yoloBox]))
    }

    func testSupportsRectangleWhenRectangleCoversMostOfYOLOBox() {
        let rectangle = CGRect(x: 0.10, y: 0.10, width: 0.20, height: 0.30)
        let yoloBox = CGRect(x: 0.11, y: 0.12, width: 0.18, height: 0.24)

        XCTAssertGreaterThanOrEqual(
            ScanYOLOSupport.coverage(of: yoloBox, by: rectangle),
            ScanYOLOSupport.coverageThreshold
        )
        XCTAssertTrue(ScanYOLOSupport.supports(rectangle: rectangle, with: [yoloBox]))
    }

    func testRejectsSmallFeatureBoxInsideLargerYOLOCardBox() {
        let featureRectangle = CGRect(x: 0.18, y: 0.22, width: 0.07, height: 0.09)
        let yoloCardBox = CGRect(x: 0.10, y: 0.10, width: 0.22, height: 0.34)

        XCTAssertLessThan(RectangleFilter.iou(featureRectangle, yoloCardBox), ScanYOLOSupport.iouThreshold)
        XCTAssertLessThan(
            ScanYOLOSupport.coverage(of: yoloCardBox, by: featureRectangle),
            ScanYOLOSupport.coverageThreshold
        )
        XCTAssertFalse(ScanYOLOSupport.supports(rectangle: featureRectangle, with: [yoloCardBox]))
    }

    func testValidateKeepsPeerRectanglesWhenYOLOOnlyFindsOneCardInMultiCardScene() {
        let left = makeObservation(
            box: CGRect(x: 0.412, y: 0.038, width: 0.163, height: 0.263),
            confidence: 1.0
        )
        let middle = makeObservation(
            box: CGRect(x: 0.399, y: 0.310, width: 0.155, height: 0.276),
            confidence: 1.0
        )
        let right = makeObservation(
            box: CGRect(x: 0.389, y: 0.565, width: 0.141, height: 0.266),
            confidence: 1.0
        )
        let yoloBox = middle.boundingBox

        let result = ScanYOLOSupport.validate([left, middle, right], with: [yoloBox])

        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(result.yoloAcceptedCount, 1)
        XCTAssertEqual(result.yoloRejectedCount, 0)
        XCTAssertEqual(result.observations.count, 3)
        XCTAssertEqual(result.observations.map(\.boundingBox), [left, middle, right].map(\.boundingBox))
    }

    func testValidateDoesNotRecoverSmallFeatureBoxFromSingleYOLOMatchedCard() {
        let card = makeObservation(
            box: CGRect(x: 0.10, y: 0.10, width: 0.20, height: 0.30),
            confidence: 0.95
        )
        let nestedFeature = makeObservation(
            box: CGRect(x: 0.17, y: 0.20, width: 0.06, height: 0.09),
            confidence: 0.92
        )

        let result = ScanYOLOSupport.validate([card, nestedFeature], with: [card.boundingBox])

        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(result.yoloAcceptedCount, 1)
        XCTAssertEqual(result.yoloRejectedCount, 1)
        XCTAssertEqual(result.observations.count, 1)
        XCTAssertEqual(result.observations[0].boundingBox, card.boundingBox)
    }

    func testValidateKeepsThreeCardsWhenYOLOMissesPerspectiveDistortedPeer() {
        let top = makeObservation(
            box: CGRect(x: 0.210, y: 0.664, width: 0.132, height: 0.317),
            confidence: 1.0
        )
        let left = makeObservation(
            box: CGRect(x: 0.302, y: 0.211, width: 0.130, height: 0.214),
            confidence: 1.0
        )
        let right = makeObservation(
            box: CGRect(x: 0.477, y: 0.193, width: 0.158, height: 0.234),
            confidence: 1.0
        )

        let result = ScanYOLOSupport.validate([right, left, top], with: [right.boundingBox, left.boundingBox])

        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(result.yoloAcceptedCount, 2)
        XCTAssertEqual(result.yoloRejectedCount, 0)
        XCTAssertEqual(result.observations.count, 3)
        XCTAssertEqual(result.observations.map(\.boundingBox), [right, left, top].map(\.boundingBox))
    }

    func testValidateRecoversRejectedPeerWhenYOLOBoxesIncludeAggregateInsteadOfThirdCard() {
        let lowerRight = makeObservation(
            box: CGRect(x: 0.429, y: 0.185, width: 0.169, height: 0.241),
            confidence: 1.0
        )
        let left = makeObservation(
            box: CGRect(x: 0.237, y: 0.175, width: 0.138, height: 0.228),
            confidence: 1.0
        )
        let upperRight = makeObservation(
            box: CGRect(x: 0.435, y: 0.665, width: 0.137, height: 0.238),
            confidence: 1.0
        )
        let aggregate = CGRect(x: 0.412, y: 0.429, width: 0.186, height: 0.503)

        let result = ScanYOLOSupport.validate(
            [lowerRight, left, upperRight],
            with: [aggregate, lowerRight.boundingBox, left.boundingBox]
        )

        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(result.yoloAcceptedCount, 2)
        XCTAssertEqual(result.yoloRejectedCount, 0)
        XCTAssertEqual(result.observations.count, 3)
        XCTAssertEqual(result.observations.map(\.boundingBox), [lowerRight, left, upperRight].map(\.boundingBox))
    }

    func testValidateRecoversLeftPeerWhenYOLOOnlyAcceptsTwoRightCards() {
        let lowerRight = makeObservation(
            box: CGRect(x: 0.357, y: 0.151, width: 0.221, height: 0.318),
            confidence: 1.0
        )
        let upperRight = makeObservation(
            box: CGRect(x: 0.345, y: 0.481, width: 0.231, height: 0.374),
            confidence: 1.0
        )
        let left = makeObservation(
            box: CGRect(x: 0.154, y: 0.163, width: 0.171, height: 0.289),
            confidence: 1.0
        )

        let result = ScanYOLOSupport.validate(
            [lowerRight, upperRight, left],
            with: [lowerRight.boundingBox, upperRight.boundingBox]
        )

        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(result.yoloAcceptedCount, 2)
        XCTAssertEqual(result.yoloRejectedCount, 0)
        XCTAssertEqual(result.observations.count, 3)
        XCTAssertEqual(result.observations.map(\.boundingBox), [lowerRight, upperRight, left].map(\.boundingBox))
    }

    func testRejectsRectangleWithoutAnySupportingYOLOBox() {
        let rectangle = CGRect(x: 0.10, y: 0.10, width: 0.20, height: 0.30)
        let yoloBox = CGRect(x: 0.70, y: 0.70, width: 0.15, height: 0.20)

        XCTAssertFalse(ScanYOLOSupport.supports(rectangle: rectangle, with: [yoloBox]))
    }

    func testValidateRejectsRectanglesWhenYOLORunsButFindsNoCards() {
        let observation = makeObservation(
            box: CGRect(x: 0.10, y: 0.10, width: 0.20, height: 0.30),
            confidence: 0.90
        )

        let result = ScanYOLOSupport.validate([observation], with: [])

        XCTAssertTrue(result.usedFallback)
        XCTAssertEqual(result.yoloAcceptedCount, 0)
        XCTAssertEqual(result.yoloRejectedCount, 0)
        XCTAssertEqual(result.observations.count, 1)
        XCTAssertEqual(result.observations[0].boundingBox, observation.boundingBox)
    }

    func testValidateFallsBackWhenYOLOSupportsNoneOfCoherentTwoCardScene() {
        let lower = makeObservation(
            box: CGRect(x: 0.426, y: 0.201, width: 0.234, height: 0.341),
            confidence: 1.0
        )
        let upper = makeObservation(
            box: CGRect(x: 0.386, y: 0.530, width: 0.209, height: 0.355),
            confidence: 1.0
        )
        let unrelatedBoxes = [
            CGRect(x: 0.05, y: 0.05, width: 0.10, height: 0.10)
        ]

        let result = ScanYOLOSupport.validate([lower, upper], with: unrelatedBoxes)

        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(result.yoloAcceptedCount, 0)
        XCTAssertEqual(result.yoloRejectedCount, 0)
        XCTAssertEqual(result.observations.count, 2)
        XCTAssertEqual(result.observations.map(\.boundingBox), [lower, upper].map(\.boundingBox))
    }

    func testValidateFallsBackWhenYOLOIsUnavailable() {
        let observation = makeObservation(
            box: CGRect(x: 0.10, y: 0.10, width: 0.20, height: 0.30),
            confidence: 0.90
        )

        let result = ScanYOLOSupport.validate([observation], with: nil)

        XCTAssertTrue(result.usedFallback)
        XCTAssertEqual(result.yoloAcceptedCount, 0)
        XCTAssertEqual(result.yoloRejectedCount, 0)
        XCTAssertEqual(result.observations.count, 1)
        XCTAssertEqual(result.observations[0].boundingBox, observation.boundingBox)
    }

    func testValidateRejectsNestedFeatureWhenOuterRectangleHasYOLOSupport() {
        let outer = makeObservation(
            box: CGRect(x: 0.35, y: 0.20, width: 0.24, height: 0.34),
            confidence: 1.0
        )
        let inner = makeObservation(
            box: CGRect(x: 0.40, y: 0.28, width: 0.08, height: 0.12),
            confidence: 1.0
        )

        let result = ScanYOLOSupport.validate([outer, inner], with: [outer.boundingBox])

        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(result.yoloAcceptedCount, 1)
        XCTAssertEqual(result.yoloRejectedCount, 1)
        XCTAssertEqual(result.observations.count, 1)
        XCTAssertEqual(result.observations[0].boundingBox, outer.boundingBox)
    }

    func testValidateKeepsOverlappingRealCardsWhenBothHaveDirectYoloSupport() {
        let outer = makeObservation(
            box: CGRect(x: 0.32, y: 0.18, width: 0.24, height: 0.34),
            confidence: 1.0
        )
        let overlapping = makeObservation(
            box: CGRect(x: 0.37, y: 0.22, width: 0.22, height: 0.32),
            confidence: 1.0
        )

        let result = ScanYOLOSupport.validate(
            [outer, overlapping],
            with: [outer.boundingBox, overlapping.boundingBox]
        )

        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(result.yoloAcceptedCount, 2)
        XCTAssertEqual(result.yoloRejectedCount, 0)
        XCTAssertEqual(result.observations.map(\.boundingBox), [outer, overlapping].map(\.boundingBox))
    }

    func testValidateDoesNotTreatArbitrarilyLargerRectangleAsYoloSupported() {
        let actualCard = makeObservation(
            box: CGRect(x: 0.34, y: 0.22, width: 0.20, height: 0.30),
            confidence: 1.0
        )
        let oversized = makeObservation(
            box: CGRect(x: 0.24, y: 0.12, width: 0.40, height: 0.50),
            confidence: 1.0
        )

        let result = ScanYOLOSupport.validate([actualCard, oversized], with: [actualCard.boundingBox])

        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(result.yoloAcceptedCount, 1)
        XCTAssertEqual(result.yoloRejectedCount, 0)
        XCTAssertEqual(result.observations.map(\.boundingBox), [actualCard, oversized].map(\.boundingBox))
    }

    func testValidateTreatsSplitCardFacesAsInternalFeaturesWhenYoloOnlySupportsOuterCard() {
        let fullCard = makeObservation(
            box: CGRect(x: 0.20, y: 0.18, width: 0.24, height: 0.34),
            confidence: 1.0
        )
        let topFace = makeObservation(
            box: CGRect(x: 0.23, y: 0.35, width: 0.18, height: 0.10),
            confidence: 1.0
        )
        let bottomFace = makeObservation(
            box: CGRect(x: 0.23, y: 0.24, width: 0.18, height: 0.10),
            confidence: 1.0
        )

        let result = ScanYOLOSupport.validate(
            [fullCard, topFace, bottomFace],
            with: [fullCard.boundingBox]
        )

        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(result.yoloAcceptedCount, 1)
        XCTAssertEqual(result.yoloRejectedCount, 2)
        XCTAssertEqual(result.observations.count, 1)
        XCTAssertEqual(result.observations[0].boundingBox, fullCard.boundingBox)
    }

    private func makeObservation(box: CGRect, confidence: Float) -> VNRectangleObservation {
        let obs = VNRectangleObservation()
        obs.setValue(box, forKey: "boundingBox")
        obs.setValue(confidence, forKey: "confidence")
        obs.setValue(CGPoint(x: box.minX, y: box.maxY), forKey: "topLeft")
        obs.setValue(CGPoint(x: box.maxX, y: box.maxY), forKey: "topRight")
        obs.setValue(CGPoint(x: box.maxX, y: box.minY), forKey: "bottomRight")
        obs.setValue(CGPoint(x: box.minX, y: box.minY), forKey: "bottomLeft")
        return obs
    }
}
