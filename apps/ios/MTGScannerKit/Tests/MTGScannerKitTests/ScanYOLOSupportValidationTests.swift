import XCTest
import Vision
@testable import MTGScannerKit

final class ScanYOLOSupportValidationTests: XCTestCase {

    func testValidateFallsBackWhenYOLOSupportsNoneOfCoherentTwoCardScene() {
        let lower = makeObservation(box: CGRect(x: 0.426, y: 0.201, width: 0.234, height: 0.341), confidence: 1.0)
        let upper = makeObservation(box: CGRect(x: 0.386, y: 0.530, width: 0.209, height: 0.355), confidence: 1.0)
        let unrelatedBoxes = [CGRect(x: 0.05, y: 0.05, width: 0.10, height: 0.10)]

        let result = ScanYOLOSupport.validate([lower, upper], with: unrelatedBoxes)

        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(result.yoloAcceptedCount, 0)
        XCTAssertEqual(result.yoloRejectedCount, 0)
        XCTAssertEqual(result.observations.count, 2)
        XCTAssertEqual(result.observations.map(\.boundingBox), [lower, upper].map(\.boundingBox))
    }

    func testValidateFallsBackWhenYOLOIsUnavailable() {
        let observation = makeObservation(box: CGRect(x: 0.10, y: 0.10, width: 0.20, height: 0.30), confidence: 0.90)

        let result = ScanYOLOSupport.validate([observation], with: nil)

        XCTAssertTrue(result.usedFallback)
        XCTAssertEqual(result.yoloAcceptedCount, 0)
        XCTAssertEqual(result.yoloRejectedCount, 0)
        XCTAssertEqual(result.observations.count, 1)
        XCTAssertEqual(result.observations[0].boundingBox, observation.boundingBox)
    }

    func testValidateRejectsNestedFeatureWhenOuterRectangleHasYOLOSupport() {
        let outer = makeObservation(box: CGRect(x: 0.35, y: 0.20, width: 0.24, height: 0.34), confidence: 1.0)
        let inner = makeObservation(box: CGRect(x: 0.40, y: 0.28, width: 0.08, height: 0.12), confidence: 1.0)

        let result = ScanYOLOSupport.validate([outer, inner], with: [outer.boundingBox])

        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(result.yoloAcceptedCount, 1)
        XCTAssertEqual(result.yoloRejectedCount, 1)
        XCTAssertEqual(result.observations.count, 1)
        XCTAssertEqual(result.observations[0].boundingBox, outer.boundingBox)
    }

    func testValidateKeepsOverlappingRealCardsWhenBothHaveDirectYoloSupport() {
        let outer = makeObservation(box: CGRect(x: 0.32, y: 0.18, width: 0.24, height: 0.34), confidence: 1.0)
        let overlapping = makeObservation(box: CGRect(x: 0.37, y: 0.22, width: 0.22, height: 0.32), confidence: 1.0)

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
        let actualCard = makeObservation(box: CGRect(x: 0.34, y: 0.22, width: 0.20, height: 0.30), confidence: 1.0)
        let oversized = makeObservation(box: CGRect(x: 0.24, y: 0.12, width: 0.40, height: 0.50), confidence: 1.0)

        let result = ScanYOLOSupport.validate([actualCard, oversized], with: [actualCard.boundingBox])

        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(result.yoloAcceptedCount, 1)
        XCTAssertEqual(result.yoloRejectedCount, 0)
        XCTAssertEqual(result.observations.map(\.boundingBox), [actualCard, oversized].map(\.boundingBox))
    }

    func testValidateTreatsSplitCardFacesAsInternalFeaturesWhenYoloOnlySupportsOuterCard() {
        let fullCard = makeObservation(box: CGRect(x: 0.20, y: 0.18, width: 0.24, height: 0.34), confidence: 1.0)
        let topFace = makeObservation(box: CGRect(x: 0.23, y: 0.35, width: 0.18, height: 0.10), confidence: 1.0)
        let bottomFace = makeObservation(box: CGRect(x: 0.23, y: 0.24, width: 0.18, height: 0.10), confidence: 1.0)

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
        makeRectangleObservation(box: box, confidence: confidence)
    }
}
