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

    func testRejectsRectangleWithoutAnySupportingYOLOBox() {
        let rectangle = CGRect(x: 0.10, y: 0.10, width: 0.20, height: 0.30)
        let yoloBox = CGRect(x: 0.70, y: 0.70, width: 0.15, height: 0.20)

        XCTAssertFalse(ScanYOLOSupport.supports(rectangle: rectangle, with: [yoloBox]))
    }

    func testValidateFallsBackWhenYOLOBoxesAreEmpty() {
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
