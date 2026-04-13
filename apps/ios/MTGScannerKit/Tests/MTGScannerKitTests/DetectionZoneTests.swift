import XCTest
@testable import MTGScannerKit

final class DetectionZoneTests: XCTestCase {

    // MARK: - Full Frame Zone

    func testFullFrameDefaultValues() {
        let zone = DetectionZone.fullFrame
        XCTAssertEqual(zone.referenceRect, CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(zone.tolerance, 0)
        XCTAssertEqual(zone.minAreaFraction, 0.40)
    }

    // MARK: - Effective Rect

    func testEffectiveRectWithDefaultTolerance() {
        let zone = DetectionZone(referenceRect: CGRect(x: 0.2, y: 0.3, width: 0.6, height: 0.4), tolerance: 0.15)
        let effective = zone.effectiveRect
        XCTAssertEqual(effective.minX, 0.11, accuracy: 0.001)
        XCTAssertEqual(effective.minY, 0.24, accuracy: 0.001)
        XCTAssertEqual(effective.width, 0.78, accuracy: 0.001)
        XCTAssertEqual(effective.height, 0.52, accuracy: 0.001)
    }

    func testEffectiveRectWithZeroTolerance() {
        let zone = DetectionZone(referenceRect: CGRect(x: 0.2, y: 0.3, width: 0.6, height: 0.4), tolerance: 0)
        let effective = zone.effectiveRect
        XCTAssertEqual(effective, zone.referenceRect)
    }

    // MARK: - Center

    func testCenter() {
        let zone = DetectionZone(referenceRect: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.4))
        XCTAssertEqual(zone.center.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(zone.center.y, 0.4, accuracy: 0.001)
    }

    // MARK: - Calibrated Factory

    func testCalibratedFrom() {
        let cardBox = CGRect(x: 0.1, y: 0.2, width: 0.4, height: 0.5)
        let zone = DetectionZone.calibrated(from: cardBox, tolerance: 0.15)
        XCTAssertEqual(zone.referenceRect, cardBox)
        XCTAssertEqual(zone.tolerance, 0.15)
    }

    func testCalibratedFromDefaultTolerance() {
        let cardBox = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let zone = DetectionZone.calibrated(from: cardBox)
        XCTAssertEqual(zone.tolerance, 0.15)
    }

    func testCalibratedFromYOLO() {
        let yoloBox = CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5)
        let zone = DetectionZone.calibrated(fromYOLO: yoloBox, tolerance: 0.15)
        XCTAssertEqual(zone.referenceRect.minX, 0.2)
        XCTAssertEqual(zone.referenceRect.minY, 0.2, accuracy: 0.001)
        XCTAssertEqual(zone.referenceRect.width, 0.4)
        XCTAssertEqual(zone.referenceRect.height, 0.5)
        XCTAssertEqual(zone.tolerance, 0.15)
    }

    func testCalibratedFromYOLOConvertsTopLeftToBottomLeft() {
        let yoloBox = CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.4)
        let zone = DetectionZone.calibrated(fromYOLO: yoloBox)
        XCTAssertEqual(zone.referenceRect.minX, 0.1)
        XCTAssertEqual(zone.referenceRect.minY, 0.5, accuracy: 0.001)
        XCTAssertEqual(zone.referenceRect.maxY, 0.9, accuracy: 0.001)
    }

    // MARK: - Containment

    func testContainsFullFrameZone() {
        let zone = DetectionZone.fullFrame
        let box = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        XCTAssertTrue(zone.contains(box))
    }

    func testContainsBoxOutsideZone() {
        let zone = DetectionZone(referenceRect: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4))
        let box = CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.1)
        XCTAssertFalse(zone.contains(box))
    }

    func testContainsBoxPartiallyOutside() {
        let zone = DetectionZone(referenceRect: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4), tolerance: 0.1)
        let box = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        XCTAssertFalse(zone.contains(box))
    }

    func testContainsBoxWithTolerance() {
        let zone = DetectionZone(referenceRect: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2), tolerance: 0.15)
        let box = CGRect(x: 0.37, y: 0.37, width: 0.06, height: 0.06)
        XCTAssertTrue(zone.contains(box))
    }

    // MARK: - Size

    func testIsLargeEnoughPasses() {
        let zone = DetectionZone.fullFrame
        let sqrt40 = sqrt(0.40)
        let box = CGRect(x: 0.1, y: 0.1, width: sqrt40, height: sqrt40)
        XCTAssertTrue(zone.isLargeEnough(box))
    }

    func testIsLargeEnoughFails() {
        let zone = DetectionZone.fullFrame
        let box = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        XCTAssertFalse(zone.isLargeEnough(box))
    }

    func testIsLargeEnoughExactBoundary() {
        let zone = DetectionZone.fullFrame
        let sqrt40 = sqrt(0.40)
        let box = CGRect(x: 0, y: 0, width: sqrt40, height: sqrt40)
        XCTAssertTrue(zone.isLargeEnough(box))
    }

    func testIsLargeEnoughJustBelowBoundary() {
        let zone = DetectionZone.fullFrame
        let sqrt40 = sqrt(0.40)
        let box = CGRect(x: 0, y: 0, width: 0.632, height: 0.632)
        XCTAssertFalse(zone.isLargeEnough(box))
    }

    // MARK: - Portrait Aspect

    func testIsPortraitAspectPortraitCard() {
        let zone = DetectionZone.fullFrame
        let box = CGRect(x: 0.3, y: 0.2, width: 0.3, height: 0.6)
        XCTAssertTrue(zone.isPortraitAspect(box))
    }

    func testIsPortraitAspectLandscapeCard() {
        let zone = DetectionZone.fullFrame
        let box = CGRect(x: 0.2, y: 0.3, width: 0.6, height: 0.3)
        XCTAssertFalse(zone.isPortraitAspect(box))
    }

    func testIsPortraitAspectSquareCard() {
        let zone = DetectionZone.fullFrame
        let box = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
        XCTAssertFalse(zone.isPortraitAspect(box))
    }

    func testIsPortraitAspectZeroHeight() {
        let zone = DetectionZone.fullFrame
        let box = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0)
        XCTAssertFalse(zone.isPortraitAspect(box))
    }

    func testIsPortraitAspectNearBoundary() {
        let zone = DetectionZone.fullFrame
        let box = CGRect(x: 0.3, y: 0.2, width: 0.40, height: 0.5)
        XCTAssertTrue(zone.isPortraitAspect(box))
    }

    func testIsPortraitAspectJustAboveBoundary() {
        let zone = DetectionZone.fullFrame
        let box = CGRect(x: 0.2, y: 0.3, width: 0.41, height: 0.5)
        XCTAssertFalse(zone.isPortraitAspect(box))
    }

    // MARK: - Combined Filter

    func testCombinedFilterPasses() {
        let zone = DetectionZone(referenceRect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8), tolerance: 0.1)
        let box = CGRect(x: 0.02, y: 0.02, width: 0.6, height: 0.75)
        XCTAssertTrue(zone.contains(box))
        XCTAssertTrue(zone.isLargeEnough(box))
        XCTAssertTrue(zone.isPortraitAspect(box))
    }

    func testCombinedFilterFailsOnAspect() {
        let zone = DetectionZone(referenceRect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8), tolerance: 0.1)
        let box = CGRect(x: 0.02, y: 0.02, width: 0.75, height: 0.75)
        XCTAssertTrue(zone.contains(box))
        XCTAssertTrue(zone.isLargeEnough(box))
        XCTAssertFalse(zone.isPortraitAspect(box))
    }

    func testCombinedFilterFailsOnSize() {
        let zone = DetectionZone(referenceRect: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6), tolerance: 0.1)
        let box = CGRect(x: 0.25, y: 0.25, width: 0.35, height: 0.55)
        XCTAssertTrue(zone.contains(box))
        XCTAssertFalse(zone.isLargeEnough(box))
        XCTAssertTrue(zone.isPortraitAspect(box))
    }
}
