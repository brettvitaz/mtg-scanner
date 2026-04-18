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
        // Photo: 3024x4032 (portrait), Video: 1920x1080 (landscape)
        let yoloBox = CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5)
        let zone = DetectionZone.calibrated(
            fromYOLO: yoloBox,
            tolerance: 0.15
        )
        // Verify zone was created with expected tolerance
        XCTAssertEqual(zone.tolerance, 0.15)
        // Verify reference rect is in valid normalized range
        XCTAssertGreaterThanOrEqual(zone.referenceRect.minX, 0)
        XCTAssertLessThanOrEqual(zone.referenceRect.maxX, 1)
        XCTAssertGreaterThanOrEqual(zone.referenceRect.minY, 0)
        XCTAssertLessThanOrEqual(zone.referenceRect.maxY, 1)

        // Verify the coordinate swap happened (X<->Y with 90-degree rotation)
        // Yolo box: centerX=0.4, centerY=0.55, w=0.4, h=0.5
        // After rotation: videoCenterX=0.55, videoCenterY=0.6 (1-0.4)
        // Width/height swap: videoW=0.5, videoH=0.4
        XCTAssertNotEqual(zone.referenceRect.minX, 0.2, accuracy: 0.01) // Should be transformed
    }

    func testCalibratedFromYOLOConvertsTopLeftToBottomLeft() {
        // Square aspect ratio test - demonstrates 90-degree rotation + Vision Y-flip
        // With square, aspect ratios match, so it's pure rotation
        let yoloBox = CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.4)
        let zone = DetectionZone.calibrated(fromYOLO: yoloBox, tolerance: 0.15)

        // Yolo box: center=(0.25, 0.3), size=(0.3, 0.4)
        // After 90-degree rotation:
        //   videoCenterX = 0.3 (was Yolo Y)
        //   videoCenterY = 0.75 (1 - 0.25, was 1 - Yolo X)
        //   videoW = 0.4 (was height)
        //   videoH = 0.3 (was width)
        // Video box: minX=0.1, maxX=0.5, minY=0.6, maxY=0.9
        // After Vision Y-flip (bottom-left origin):
        //   visionMinY = 1.0 - 0.9 = 0.1
        //   visionMaxY = 1.0 - 0.6 = 0.4
        XCTAssertEqual(zone.referenceRect.minX, 0.1, accuracy: 0.001)
        XCTAssertEqual(zone.referenceRect.minY, 0.1, accuracy: 0.001)
        XCTAssertEqual(zone.referenceRect.maxX, 0.5, accuracy: 0.001)
        XCTAssertEqual(zone.referenceRect.maxY, 0.4, accuracy: 0.001)
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

    // MARK: - Uncalibrated Zone

    func testUncalibratedZoneDefaults() {
        let zone = DetectionZone.uncalibrated
        XCTAssertEqual(zone.referenceRect, CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8))
        XCTAssertEqual(zone.tolerance, 0)
        XCTAssertEqual(zone.minAreaFraction, 0)       // no size constraint before calibration
        XCTAssertEqual(zone.maxPortraitAspectRatio, 0.8)
    }

    func testUncalibratedZoneRejectsEdgeBox() {
        // Box at top-left corner — fails containment
        let zone = DetectionZone.uncalibrated
        let box = CGRect(x: 0.0, y: 0.85, width: 0.15, height: 0.25)  // Vision coords (bottom-left origin)
        XCTAssertFalse(zone.contains(box))
    }

    func testUncalibratedZoneAcceptsSmallCenteredBox() {
        // Box centered but small — passes because size is not constrained pre-calibration
        let zone = DetectionZone.uncalibrated
        let box = CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.42)  // aspect = 0.71, area = 0.126
        XCTAssertTrue(zone.contains(box))
        XCTAssertTrue(zone.isLargeEnough(box))   // minAreaFraction = 0
        XCTAssertTrue(zone.isPortraitAspect(box))
    }

    func testUncalibratedZoneRejectsLandscapeBox() {
        // Landscape aspect ratio — fails portrait check
        let zone = DetectionZone.uncalibrated
        let box = CGRect(x: 0.15, y: 0.25, width: 0.7, height: 0.5)  // aspect = 1.4
        XCTAssertTrue(zone.contains(box))
        XCTAssertFalse(zone.isPortraitAspect(box))
    }

    func testUncalibratedZoneAcceptsGoodCenteredCard() {
        // Portrait card near center — passes containment and aspect ratio
        let zone = DetectionZone.uncalibrated
        let box = CGRect(x: 0.25, y: 0.15, width: 0.5, height: 0.7)  // aspect = 0.71
        XCTAssertTrue(zone.contains(box))
        XCTAssertTrue(zone.isLargeEnough(box))
        XCTAssertTrue(zone.isPortraitAspect(box))
    }

}

// MARK: - Center Proximity Tests

final class DetectionZoneCenterProximityTests: XCTestCase {

    func testCenterProximityRadiusDerivation() {
        // radius = max(w, h) / 2 * (1 + tolerance)
        let zone = DetectionZone(referenceRect: CGRect(x: 0.3, y: 0.2, width: 0.4, height: 0.6), tolerance: 0.15)
        XCTAssertEqual(zone.centerProximityRadius, 0.345, accuracy: 0.001)
    }

    func testCenterProximityRadiusWithZeroTolerance() {
        let zone = DetectionZone(referenceRect: CGRect(x: 0.3, y: 0.2, width: 0.4, height: 0.6), tolerance: 0)
        XCTAssertEqual(zone.centerProximityRadius, 0.3, accuracy: 0.001)
    }

    func testContainsCenterAcceptsCenteredBoxAtCalibratedSize() {
        let cardBox = CGRect(x: 0.3, y: 0.2, width: 0.4, height: 0.6)
        let zone = DetectionZone.calibrated(from: cardBox, tolerance: 0.15)
        XCTAssertTrue(zone.containsCenter(of: cardBox))
    }

    func testContainsCenterAcceptsLargerCenteredBox() {
        // 1.5× size at same center — simulates stack growth. Old containment check would reject.
        let cardBox = CGRect(x: 0.3, y: 0.2, width: 0.4, height: 0.6)
        let zone = DetectionZone.calibrated(from: cardBox, tolerance: 0.15)
        let largerBox = CGRect(x: cardBox.midX - 0.3, y: cardBox.midY - 0.45, width: 0.6, height: 0.9)
        XCTAssertFalse(zone.contains(largerBox))
        XCTAssertTrue(zone.containsCenter(of: largerBox))
    }

    func testContainsCenterRejectsBoxAtFrameEdge() {
        let zone = DetectionZone.calibrated(from: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4), tolerance: 0.15)
        let edgeBox = CGRect(x: 0.0, y: 0.8, width: 0.15, height: 0.2)
        XCTAssertFalse(zone.containsCenter(of: edgeBox))
    }

    func testContainsCenterRespectsTolerance() {
        // ref center=(0.5,0.5), tight radius=0.15, loose radius=0.225
        // box center=(0.70,0.50) → distance=0.2 → outside tight, inside loose
        let ref = CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3)
        let tight = DetectionZone(referenceRect: ref, tolerance: 0.0)
        let loose = DetectionZone(referenceRect: ref, tolerance: 0.5)
        let box = CGRect(x: 0.65, y: 0.45, width: 0.1, height: 0.1)
        XCTAssertFalse(tight.containsCenter(of: box))
        XCTAssertTrue(loose.containsCenter(of: box))
    }

    func testUncalibratedZoneCenterProximityCoversCenter() {
        let zone = DetectionZone.uncalibrated
        let centeredCard = CGRect(x: 0.3, y: 0.2, width: 0.4, height: 0.6)
        XCTAssertTrue(zone.containsCenter(of: centeredCard))
    }

    func testUncalibratedZoneCenterProximityRejectsExtremeEdge() {
        let zone = DetectionZone.uncalibrated
        let edgeCard = CGRect(x: 0.0, y: 0.0, width: 0.15, height: 0.2)  // center=(0.075, 0.1)
        XCTAssertFalse(zone.containsCenter(of: edgeCard))
    }
}
