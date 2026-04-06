import XCTest
@testable import MTGScannerKit

final class DetectedCardTests: XCTestCase {

    // MARK: - DetectedCard

    func testDetectedCardInitializesWithProvidedValues() {
        let id = UUID()
        let box = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        let card = DetectedCard(
            id: id,
            boundingBox: box,
            topLeft: CGPoint(x: 0.1, y: 0.6),
            topRight: CGPoint(x: 0.4, y: 0.6),
            bottomRight: CGPoint(x: 0.4, y: 0.2),
            bottomLeft: CGPoint(x: 0.1, y: 0.2),
            confidence: 0.85,
            timestamp: 1.5
        )

        XCTAssertEqual(card.id, id)
        XCTAssertEqual(card.boundingBox, box)
        XCTAssertEqual(card.topLeft, CGPoint(x: 0.1, y: 0.6))
        XCTAssertEqual(card.topRight, CGPoint(x: 0.4, y: 0.6))
        XCTAssertEqual(card.bottomRight, CGPoint(x: 0.4, y: 0.2))
        XCTAssertEqual(card.bottomLeft, CGPoint(x: 0.1, y: 0.2))
        XCTAssertEqual(card.confidence, 0.85, accuracy: 0.001)
        XCTAssertEqual(card.timestamp, 1.5, accuracy: 0.001)
    }

    func testDetectedCardDefaultIdIsUnique() {
        let card1 = DetectedCard(
            boundingBox: .zero, topLeft: .zero, topRight: .zero,
            bottomRight: .zero, bottomLeft: .zero, confidence: 0.5
        )
        let card2 = DetectedCard(
            boundingBox: .zero, topLeft: .zero, topRight: .zero,
            bottomRight: .zero, bottomLeft: .zero, confidence: 0.5
        )
        XCTAssertNotEqual(card1.id, card2.id)
    }

    func testDetectedCardDefaultTimestampIsZero() {
        let card = DetectedCard(
            boundingBox: .zero, topLeft: .zero, topRight: .zero,
            bottomRight: .zero, bottomLeft: .zero, confidence: 0.5
        )
        XCTAssertEqual(card.timestamp, 0)
    }

    func testDetectedCardEquatableByValue() {
        let id = UUID()
        let box = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        let card1 = DetectedCard(
            id: id, boundingBox: box,
            topLeft: .zero, topRight: .zero, bottomRight: .zero, bottomLeft: .zero,
            confidence: 0.9, timestamp: 2.0
        )
        let card2 = DetectedCard(
            id: id, boundingBox: box,
            topLeft: .zero, topRight: .zero, bottomRight: .zero, bottomLeft: .zero,
            confidence: 0.9, timestamp: 2.0
        )
        XCTAssertEqual(card1, card2)
    }

    func testDetectedCardIdentifiableByID() {
        let id = UUID()
        let card = DetectedCard(
            id: id, boundingBox: .zero,
            topLeft: .zero, topRight: .zero, bottomRight: .zero, bottomLeft: .zero,
            confidence: 0.5
        )
        XCTAssertEqual(card.id, id)
    }

    // MARK: - DetectionMode

    func testDetectionModeScanRawValue() {
        XCTAssertEqual(DetectionMode.scan.rawValue, "scan")
    }

    func testDetectionModeAutoRawValue() {
        XCTAssertEqual(DetectionMode.auto.rawValue, "auto")
    }

    func testDetectionModeAllCasesContainsScanAndAuto() {
        XCTAssertEqual(DetectionMode.allCases, [.scan, .auto])
    }

    func testDetectionModeIdentifiableUsesRawValue() {
        XCTAssertEqual(DetectionMode.scan.id, "scan")
        XCTAssertEqual(DetectionMode.auto.id, "auto")
    }

    func testDetectionModeRoundtripsViaRawValue() {
        XCTAssertEqual(DetectionMode(rawValue: "scan"), .scan)
        XCTAssertEqual(DetectionMode(rawValue: "auto"), .auto)
        XCTAssertNil(DetectionMode(rawValue: "unknown"))
    }
}
