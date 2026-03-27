import XCTest
import Vision
@testable import MTGScanner

final class RectangleFilterTests: XCTestCase {

    private let filter = RectangleFilter()

    // MARK: - Constants

    func testTargetAspectRatioApproximatesMTGCard() {
        // 63mm / 88mm ≈ 0.716
        XCTAssertEqual(RectangleFilter.targetAspectRatio, 63.0 / 88.0, accuracy: 0.001)
    }

    // MARK: - IoU

    func testIouOfIdenticalRectanglesIsOne() {
        let rect = CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.4)
        XCTAssertEqual(RectangleFilter.iou(rect, rect), 1.0, accuracy: 0.001)
    }

    func testIouOfNonOverlappingRectanglesIsZero() {
        let a = CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2)
        let b = CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2)
        XCTAssertEqual(RectangleFilter.iou(a, b), 0.0, accuracy: 0.001)
    }

    func testIouOfHalfOverlapIsCorrect() {
        // a covers [0, 0.4] × [0, 1.0], b covers [0.2, 0.6] × [0, 1.0]
        // intersection: [0.2, 0.4] × [0, 1.0] = 0.2 × 1.0 = 0.2
        // union: 0.4 + 0.4 - 0.2 = 0.6
        let a = CGRect(x: 0.0, y: 0.0, width: 0.4, height: 1.0)
        let b = CGRect(x: 0.2, y: 0.0, width: 0.4, height: 1.0)
        XCTAssertEqual(RectangleFilter.iou(a, b), 0.2 / 0.6, accuracy: 0.001)
    }

    func testIouWithZeroAreaRectangleIsZero() {
        let a = CGRect(x: 0.1, y: 0.1, width: 0.0, height: 0.4)
        let b = CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.4)
        XCTAssertEqual(RectangleFilter.iou(a, b), 0.0, accuracy: 0.001)
    }

    // MARK: - Aspect ratio acceptance

    func testFilterAcceptsExactCardAspectRatio() {
        // Create an observation whose bounding box matches the card ratio exactly.
        let ratio = RectangleFilter.targetAspectRatio  // short/long
        // Make a portrait box: width = ratio, height = 1.0 (scaled to fit 0...1)
        let height: CGFloat = 0.4
        let width = height * ratio
        let obs = makeObservation(box: CGRect(x: 0.1, y: 0.1, width: width, height: height), confidence: 0.9)
        let result = filter.filter([obs])
        XCTAssertEqual(result.count, 1)
    }

    func testFilterRejectsTooNarrowAspectRatio() {
        // A very narrow rectangle (like a pencil) should be rejected.
        let obs = makeObservation(box: CGRect(x: 0.1, y: 0.1, width: 0.05, height: 0.4), confidence: 0.9)
        let result = filter.filter([obs])
        XCTAssertEqual(result.count, 0)
    }

    func testFilterRejectsTooWideAspectRatio() {
        // A nearly-square rectangle should be rejected.
        let obs = makeObservation(box: CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.42), confidence: 0.9)
        let result = filter.filter([obs])
        XCTAssertEqual(result.count, 0)
    }

    func testFilterRejectsLowConfidence() {
        let ratio = RectangleFilter.targetAspectRatio
        let height: CGFloat = 0.4
        let width = height * ratio
        let obs = makeObservation(box: CGRect(x: 0.1, y: 0.1, width: width, height: height), confidence: 0.1)
        let result = filter.filter([obs])
        XCTAssertEqual(result.count, 0)
    }

    func testFilterAcceptsAtMinimumConfidence() {
        let ratio = RectangleFilter.targetAspectRatio
        let height: CGFloat = 0.4
        let width = height * ratio
        let obs = makeObservation(box: CGRect(x: 0.1, y: 0.1, width: width, height: height), confidence: RectangleFilter.minConfidence)
        let result = filter.filter([obs])
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - NMS

    func testFilterSuppressesHeavilyOverlappingDuplicates() {
        // Two nearly-identical card-shaped boxes — only the higher-confidence one should survive.
        let ratio = RectangleFilter.targetAspectRatio
        let height: CGFloat = 0.4
        let width = height * ratio
        let high = makeObservation(box: CGRect(x: 0.1, y: 0.1, width: width, height: height), confidence: 0.9)
        // Slightly shifted but IoU >> 0.45
        let low = makeObservation(box: CGRect(x: 0.102, y: 0.102, width: width, height: height), confidence: 0.6)
        let result = filter.filter([low, high])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first!.confidence, 0.9, accuracy: 0.001)
    }

    func testFilterPreservesNonOverlappingDetections() {
        let ratio = RectangleFilter.targetAspectRatio
        let height: CGFloat = 0.3
        let width = height * ratio
        // Place two cards far apart (no IoU overlap).
        let left = makeObservation(box: CGRect(x: 0.0, y: 0.1, width: width, height: height), confidence: 0.8)
        let right = makeObservation(box: CGRect(x: 0.6, y: 0.1, width: width, height: height), confidence: 0.7)
        let result = filter.filter([left, right])
        XCTAssertEqual(result.count, 2)
    }

    func testFilterReturnsEmptyForEmptyInput() {
        XCTAssertEqual(filter.filter([]).count, 0)
    }

    // MARK: - Spatial sort

    func testSpatialSortComparatorOrdersLowerMinYFirst() {
        // VNRectangleObservation.boundingBox cannot be set via KVC on modern Vision,
        // so we test the sort comparator logic directly on CGRect values.
        // The sort matches RectangleFilter.filter: ascending minY, with ties broken by minX.
        // In Vision normalized coords (origin bottom-left), lower minY = closer to bottom of frame.
        let boxes: [CGRect] = [
            CGRect(x: 0.1, y: 0.70, width: 0.18, height: 0.25),  // high minY (top region)
            CGRect(x: 0.1, y: 0.05, width: 0.18, height: 0.25),  // low minY (bottom region)
            CGRect(x: 0.5, y: 0.05, width: 0.18, height: 0.25),  // low minY, right side
        ]
        // Replicate the sort comparator from RectangleFilter.filter:
        let sorted = boxes.sorted { a, b in
            let ay = a.minY
            let by = b.minY
            if abs(ay - by) > 0.05 { return ay < by }
            return a.minX < b.minX
        }
        // Expect: ascending minY → bottom-row first, then top.
        XCTAssertEqual(sorted[0].minY, 0.05, accuracy: 0.001)
        XCTAssertEqual(sorted[0].minX, 0.1, accuracy: 0.001)
        XCTAssertEqual(sorted[1].minY, 0.05, accuracy: 0.001)
        XCTAssertEqual(sorted[1].minX, 0.5, accuracy: 0.001)
        XCTAssertEqual(sorted[2].minY, 0.70, accuracy: 0.001)
    }

    // MARK: - Helpers

    /// Creates a VNRectangleObservation with a given bounding box and confidence.
    ///
    /// VNRectangleObservation cannot be directly initialized; we use KVC to set properties.
    private func makeObservation(box: CGRect, confidence: Float) -> VNRectangleObservation {
        let obs = VNRectangleObservation()
        obs.setValue(box, forKey: "boundingBox")
        obs.setValue(confidence, forKey: "confidence")
        return obs
    }
}
