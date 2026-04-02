import XCTest
@testable import MTGScanner

final class YOLOCardDetectorTests: XCTestCase {

    // MARK: - IoU

    func testIoUIdentical() {
        let box = CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        XCTAssertEqual(YOLOCardDetector.iou(box, box), 1.0, accuracy: 0.001)
    }

    func testIoUNoOverlap() {
        let a = CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2)
        let b = CGRect(x: 0.8, y: 0.8, width: 0.2, height: 0.2)
        XCTAssertEqual(YOLOCardDetector.iou(a, b), 0.0, accuracy: 0.001)
    }

    func testIoUPartialOverlap() {
        // a = [0, 0, 0.3, 0.2], b = [0.2, 0, 0.3, 0.2] → overlap = 0.1 × 0.2
        let a = CGRect(x: 0.0, y: 0.0, width: 0.3, height: 0.2)
        let b = CGRect(x: 0.2, y: 0.0, width: 0.3, height: 0.2)
        let intersection: CGFloat = 0.1 * 0.2
        let union: CGFloat = 0.3 * 0.2 + 0.3 * 0.2 - intersection
        let expected = Float(intersection / union)
        XCTAssertEqual(YOLOCardDetector.iou(a, b), expected, accuracy: 0.001)
    }

    // MARK: - NMS

    func testNMSSuppressesHighIoUDuplicate() {
        let boxes: [(rect: CGRect, confidence: Float)] = [
            (CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.4), 0.9),
            (CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.4), 0.6)
        ]
        let result = YOLOCardDetector.nonMaxSuppression(boxes)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].confidence, 0.9, accuracy: 0.001)
    }

    func testNMSKeepsNonOverlappingBoxes() {
        let boxes: [(rect: CGRect, confidence: Float)] = [
            (CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2), 0.9),
            (CGRect(x: 0.8, y: 0.8, width: 0.2, height: 0.2), 0.8)
        ]
        let result = YOLOCardDetector.nonMaxSuppression(boxes)
        XCTAssertEqual(result.count, 2)
    }

    func testNMSEmptyInput() {
        XCTAssertEqual(YOLOCardDetector.nonMaxSuppression([]).count, 0)
    }

    func testNMSSingleBox() {
        let boxes: [(rect: CGRect, confidence: Float)] = [
            (CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3), 0.75)
        ]
        let result = YOLOCardDetector.nonMaxSuppression(boxes)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].confidence, 0.75, accuracy: 0.001)
    }

    func testNMSOrdersByConfidence() {
        let boxes: [(rect: CGRect, confidence: Float)] = [
            (CGRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2), 0.6),
            (CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2), 0.9)
        ]
        let result = YOLOCardDetector.nonMaxSuppression(boxes)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].confidence, 0.9, accuracy: 0.001)
    }
}
