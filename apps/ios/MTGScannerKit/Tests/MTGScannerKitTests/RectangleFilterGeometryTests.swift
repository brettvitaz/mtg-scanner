import XCTest
@testable import MTGScannerKit

final class RectangleFilterGeometryTests: XCTestCase {

    func testTargetAspectRatioApproximatesMTGCard() {
        XCTAssertEqual(RectangleFilter.targetAspectRatio, 63.0 / 88.0, accuracy: 0.001)
    }

    func testPortraitInBufferRatioIsTargetScaledByBufferRatio() {
        let expected = RectangleFilter.targetAspectRatio * (1080.0 / 1920.0)
        XCTAssertEqual(RectangleFilter.portraitInBufferRatio, expected, accuracy: 0.001)
    }

    func testIouOfIdenticalRectanglesIsOne() {
        let rect = CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.4)
        XCTAssertEqual(RectangleFilter.iou(rect, rect), 1.0, accuracy: 0.001)
    }

    func testIouOfNonOverlappingRectanglesIsZero() {
        let first = CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2)
        let second = CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2)
        XCTAssertEqual(RectangleFilter.iou(first, second), 0.0, accuracy: 0.001)
    }

    func testIouOfHalfOverlapIsCorrect() {
        let first = CGRect(x: 0.0, y: 0.0, width: 0.4, height: 1.0)
        let second = CGRect(x: 0.2, y: 0.0, width: 0.4, height: 1.0)
        XCTAssertEqual(RectangleFilter.iou(first, second), 0.2 / 0.6, accuracy: 0.001)
    }

    func testIouWithZeroAreaRectangleIsZero() {
        let first = CGRect(x: 0.1, y: 0.1, width: 0.0, height: 0.4)
        let second = CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.4)
        XCTAssertEqual(RectangleFilter.iou(first, second), 0.0, accuracy: 0.001)
    }

    func testContainmentRatioOfFullyContainedRectangleIsOne() {
        let inner = CGRect(x: 0.2, y: 0.2, width: 0.2, height: 0.3)
        let outer = CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.6)
        XCTAssertEqual(RectangleFilter.containmentRatio(of: inner, in: outer), 1.0, accuracy: 0.001)
    }

    func testVisionBoundsIncludePortraitAndLandscape() {
        let portraitRatio: Float = Float(63.0 / 88.0)
        let landscapeRatio: Float = Float(88.0 / 63.0)

        XCTAssertTrue(RectangleFilter.visionMinAspectRatio <= portraitRatio)
        XCTAssertTrue(RectangleFilter.visionMaxAspectRatio >= landscapeRatio)
    }

    func testVisionBoundsAreWiderThanEdgeFilter() {
        let edgeLower = Float(RectangleFilter.targetAspectRatio * (1 - RectangleFilter.scanAspectRatioTolerance))
        XCTAssertTrue(RectangleFilter.visionMinAspectRatio < edgeLower)
    }
}
