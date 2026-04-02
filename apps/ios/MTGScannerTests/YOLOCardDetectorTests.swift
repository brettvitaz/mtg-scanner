import CoreML
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

    func testDecodeUsesMultiArrayStrides() throws {
        let output = try makeStridedOutput()

        let result = YOLOCardDetector.decode(output: output, confidenceThreshold: 0.5)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].rect.origin.x, 0.65, accuracy: 0.001)
        XCTAssertEqual(result[0].rect.origin.y, 0.125, accuracy: 0.001)
        XCTAssertEqual(result[0].rect.width, 0.1, accuracy: 0.001)
        XCTAssertEqual(result[0].rect.height, 0.15, accuracy: 0.001)
        XCTAssertEqual(result[1].rect.origin.x, 0.3, accuracy: 0.001)
        XCTAssertEqual(result[1].rect.origin.y, 0.35, accuracy: 0.001)
        XCTAssertEqual(result[1].rect.width, 0.2, accuracy: 0.001)
        XCTAssertEqual(result[1].rect.height, 0.3, accuracy: 0.001)
    }

    private func makeStridedOutput() throws -> MLMultiArray {
        let shape = [1, 5, 2].map(NSNumber.init(value:))
        let strides = [40, 7, 3].map(NSNumber.init(value:))
        let pointer = UnsafeMutablePointer<Float32>.allocate(capacity: 32)
        pointer.initialize(repeating: 0, count: 32)

        let output = try MLMultiArray(
            dataPointer: pointer,
            shape: shape,
            dataType: .float32,
            strides: strides
        ) { rawPointer in
            rawPointer.assumingMemoryBound(to: Float32.self).deallocate()
        }

        // Raw tensor values are absolute pixel coordinates in the 640×640 model input space.
        // cx=256, cy=320 → normalized center (0.4, 0.5); w=128, h=192 → (0.2, 0.3)
        pointer[0] = 256    // cx anchor0
        pointer[7] = 320    // cy anchor0
        pointer[14] = 128   // w anchor0
        pointer[21] = 192   // h anchor0
        pointer[28] = 0.75  // confidence anchor0 (not a coordinate — not divided by 640)
        // cx=448, cy=128 → normalized center (0.7, 0.2); w=64, h=96 → (0.1, 0.15)
        pointer[3] = 448    // cx anchor1
        pointer[10] = 128   // cy anchor1
        pointer[17] = 64    // w anchor1
        pointer[24] = 96    // h anchor1
        pointer[31] = 0.8   // confidence anchor1

        return output
    }
}
