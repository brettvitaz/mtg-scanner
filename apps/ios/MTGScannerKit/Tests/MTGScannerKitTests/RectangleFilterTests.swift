import XCTest
import Vision
@testable import MTGScannerKit

final class RectangleFilterTests: XCTestCase {

    private let filter = RectangleFilter()
    private let cropFilter = RectangleFilter(configuration: .crop)

    // MARK: - Constants

    func testTargetAspectRatioApproximatesMTGCard() {
        // 63mm / 88mm ≈ 0.716
        XCTAssertEqual(RectangleFilter.targetAspectRatio, 63.0 / 88.0, accuracy: 0.001)
    }

    func testPortraitInBufferRatioIsTargetScaledByBufferRatio() {
        // The 1920×1080 buffer compresses normalized x by 9/16 relative to y.
        // A card standing upright in landscape mode appears with ratio ≈ target × (1080/1920).
        let expected = RectangleFilter.targetAspectRatio * (1080.0 / 1920.0)
        XCTAssertEqual(RectangleFilter.portraitInBufferRatio, expected, accuracy: 0.001)
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

    func testContainmentRatioOfFullyContainedRectangleIsOne() {
        let inner = CGRect(x: 0.2, y: 0.2, width: 0.2, height: 0.3)
        let outer = CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.6)
        XCTAssertEqual(RectangleFilter.containmentRatio(of: inner, in: outer), 1.0, accuracy: 0.001)
    }

    // MARK: - Aspect ratio — portrait device (isLandscape: false)

    func testFilterAcceptsExactCardAspectRatio() {
        let ratio = RectangleFilter.targetAspectRatio
        let height: CGFloat = 0.4
        let width = height * ratio
        let obs = makeObservation(box: CGRect(x: 0.1, y: 0.1, width: width, height: height), confidence: 0.9)
        let result = filter.filter([obs], isLandscape: false)
        XCTAssertEqual(result.count, 1)
    }

    func testFilterRejectsTooNarrowAspectRatio() {
        // A very narrow rectangle (like a pencil) should be rejected.
        let obs = makeObservation(box: CGRect(x: 0.1, y: 0.1, width: 0.05, height: 0.4), confidence: 0.9)
        let result = filter.filter([obs], isLandscape: false)
        XCTAssertEqual(result.count, 0)
    }

    func testFilterRejectsTooSquareAspectRatio() {
        // A nearly-square rectangle should be rejected.
        let obs = makeObservation(box: CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.42), confidence: 0.9)
        let result = filter.filter([obs], isLandscape: false)
        XCTAssertEqual(result.count, 0)
    }

    func testFilterRejectsLowConfidence() {
        let ratio = RectangleFilter.targetAspectRatio
        let height: CGFloat = 0.4
        let width = height * ratio
        let obs = makeObservation(box: CGRect(x: 0.1, y: 0.1, width: width, height: height), confidence: 0.1)
        let result = filter.filter([obs], isLandscape: false)
        XCTAssertEqual(result.count, 0)
    }

    func testFilterAcceptsAtMinimumConfidence() {
        let ratio = RectangleFilter.targetAspectRatio
        let height: CGFloat = 0.4
        let width = height * ratio
        let obs = makeObservation(
            box: CGRect(x: 0.1, y: 0.1, width: width, height: height),
            confidence: RectangleFilter.minConfidence
        )
        let result = filter.filter([obs], isLandscape: false)
        XCTAssertEqual(result.count, 1)
    }

    func testFilterAcceptsLandscapeCardAspectRatioInPortraitMode() {
        // Portrait device: card lying flat (landscape in buffer, short/long ≈ 0.716) — accepted.
        let ratio = RectangleFilter.targetAspectRatio
        let width: CGFloat = 0.4
        let height = width * ratio  // height < width → landscape bounding box
        let obs = makeObservation(box: CGRect(x: 0.1, y: 0.1, width: width, height: height), confidence: 0.9)
        let result = filter.filter([obs], isLandscape: false)
        XCTAssertEqual(result.count, 1)
    }

    func testFilterAcceptsAtLowerToleranceBound() {
        // Use a value just inside the lower bound to avoid floating-point boundary fragility.
        let lower = RectangleFilter.targetAspectRatio * (1 - RectangleFilter.scanAspectRatioTolerance)
        let height: CGFloat = 0.4
        let width = height * (lower + 0.005)
        let obs = makeObservation(box: CGRect(x: 0.1, y: 0.1, width: width, height: height), confidence: 0.9)
        let result = filter.filter([obs], isLandscape: false)
        XCTAssertEqual(result.count, 1)
    }

    func testFilterRejectsBelowLowerToleranceBound() {
        let lower = RectangleFilter.targetAspectRatio * (1 - RectangleFilter.scanAspectRatioTolerance)
        let height: CGFloat = 0.4
        let width = height * (lower - 0.01)
        let obs = makeObservation(box: CGRect(x: 0.1, y: 0.1, width: width, height: height), confidence: 0.9)
        let result = filter.filter([obs], isLandscape: false)
        XCTAssertEqual(result.count, 0)
    }

    func testFilterAcceptsAtUpperToleranceBound() {
        // Use a value just inside the upper bound to avoid floating-point boundary fragility.
        let upper = RectangleFilter.targetAspectRatio * (1 + RectangleFilter.scanAspectRatioTolerance)
        let height: CGFloat = 0.4
        let width = height * (upper - 0.005)
        let obs = makeObservation(box: CGRect(x: 0.1, y: 0.1, width: width, height: height), confidence: 0.9)
        let result = filter.filter([obs], isLandscape: false)
        XCTAssertEqual(result.count, 1)
    }

    func testFilterRejectsAboveUpperToleranceBound() {
        let upper = RectangleFilter.targetAspectRatio * (1 + RectangleFilter.scanAspectRatioTolerance)
        let height: CGFloat = 0.4
        let width = height * (upper + 0.01)
        let obs = makeObservation(box: CGRect(x: 0.1, y: 0.1, width: width, height: height), confidence: 0.9)
        let result = filter.filter([obs], isLandscape: false)
        XCTAssertEqual(result.count, 0)
    }

    // MARK: - Aspect ratio — landscape device (isLandscape: true)

    func testFilterAcceptsPortraitCardInLandscapeBuffer() {
        // Landscape device: card upright has its long axis vertical in the 1920×1080 buffer.
        // Normalized ratio = targetAspectRatio × (1080/1920) ≈ 0.402 because Vision compresses
        // x-distances by 9/16. isLandscape: true activates the portrait-in-buffer band.
        let height: CGFloat = 0.4
        let width = height * RectangleFilter.portraitInBufferRatio
        let obs = makeObservation(box: CGRect(x: 0.1, y: 0.1, width: width, height: height), confidence: 0.9)
        let result = filter.filter([obs], isLandscape: true)
        XCTAssertEqual(result.count, 1)
    }

    func testFilterRejectsHorizontalCardInLandscapeMode() {
        // Landscape device: card lying flat (landscape-in-buffer, ratio ≈ 0.716) must be rejected
        // so only upright cards are detected when the device is landscape.
        let ratio = RectangleFilter.targetAspectRatio
        let height: CGFloat = 0.4
        let width = height * ratio
        let obs = makeObservation(box: CGRect(x: 0.1, y: 0.1, width: width, height: height), confidence: 0.9)
        let result = filter.filter([obs], isLandscape: true)
        XCTAssertEqual(result.count, 0)
    }

    // MARK: - Rotated card

    func testFilterAcceptsRotatedCardWithDistortedBoundingBox() {
        // A card rotated ~45° has an AABB that doesn't reflect the true card ratio,
        // but the corner-based edge lengths should still produce the correct ratio.
        // Simulate a card with short=0.2, long=0.28 (ratio ≈ 0.714) rotated 30°.
        let shortSide: CGFloat = 0.2
        let longSide: CGFloat = 0.28
        let angle: CGFloat = .pi / 6  // 30 degrees
        let cx: CGFloat = 0.5, cy: CGFloat = 0.5

        let hw = shortSide / 2, hh = longSide / 2
        let cosA = cos(angle), sinA = sin(angle)
        func rotate(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: cx + x * cosA - y * sinA, y: cy + x * sinA + y * cosA)
        }
        let tl = rotate(-hw, hh)
        let tr = rotate(hw, hh)
        let br = rotate(hw, -hh)
        let bl = rotate(-hw, -hh)

        let minX = min(tl.x, tr.x, br.x, bl.x)
        let minY = min(tl.y, tr.y, br.y, bl.y)
        let maxX = max(tl.x, tr.x, br.x, bl.x)
        let maxY = max(tl.y, tr.y, br.y, bl.y)
        let box = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        let obs = VNRectangleObservation()
        obs.setValue(box, forKey: "boundingBox")
        obs.setValue(Float(0.9), forKey: "confidence")
        obs.setValue(tl, forKey: "topLeft")
        obs.setValue(tr, forKey: "topRight")
        obs.setValue(br, forKey: "bottomRight")
        obs.setValue(bl, forKey: "bottomLeft")

        let result = filter.filter([obs], isLandscape: false)
        XCTAssertEqual(result.count, 1)
    }

    func testFilterAcceptsPerspectiveDistortedCardNearPortraitLowerBound() {
        let obs = VNRectangleObservation()
        obs.setValue(CGRect(x: 0.210, y: 0.664, width: 0.132, height: 0.317), forKey: "boundingBox")
        obs.setValue(Float(1.0), forKey: "confidence")
        obs.setValue(CGPoint(x: 0.210, y: 0.929), forKey: "topLeft")
        obs.setValue(CGPoint(x: 0.324, y: 0.981), forKey: "topRight")
        obs.setValue(CGPoint(x: 0.342, y: 0.730), forKey: "bottomRight")
        obs.setValue(CGPoint(x: 0.220, y: 0.664), forKey: "bottomLeft")

        let result = filter.filter([obs], isLandscape: false)

        XCTAssertEqual(result.count, 1)
    }

    func testCropFilterRejectsPerspectiveDistortedCardNearPortraitLowerBound() {
        let obs = VNRectangleObservation()
        obs.setValue(CGRect(x: 0.210, y: 0.664, width: 0.132, height: 0.317), forKey: "boundingBox")
        obs.setValue(Float(1.0), forKey: "confidence")
        obs.setValue(CGPoint(x: 0.210, y: 0.929), forKey: "topLeft")
        obs.setValue(CGPoint(x: 0.324, y: 0.981), forKey: "topRight")
        obs.setValue(CGPoint(x: 0.342, y: 0.730), forKey: "bottomRight")
        obs.setValue(CGPoint(x: 0.220, y: 0.664), forKey: "bottomLeft")

        let result = cropFilter.filter([obs], isLandscape: false)

        XCTAssertTrue(result.isEmpty)
    }

    func testFilterRejectsTallAggregateBoxUnderPortraitTolerance() {
        let obs = VNRectangleObservation()
        obs.setValue(CGRect(x: 0.475, y: 0.434, width: 0.163, height: 0.451), forKey: "boundingBox")
        obs.setValue(Float(1.0), forKey: "confidence")
        obs.setValue(CGPoint(x: 0.475, y: 0.838), forKey: "topLeft")
        obs.setValue(CGPoint(x: 0.633, y: 0.885), forKey: "topRight")
        obs.setValue(CGPoint(x: 0.638, y: 0.434), forKey: "bottomRight")
        obs.setValue(CGPoint(x: 0.480, y: 0.436), forKey: "bottomLeft")

        let result = filter.filter([obs], isLandscape: false)

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Vision bounds

    func testVisionBoundsIncludePortraitAndLandscape() {
        let portraitRatio: Float = Float(63.0 / 88.0)
        let landscapeRatio: Float = Float(88.0 / 63.0)

        XCTAssertTrue(RectangleFilter.visionMinAspectRatio <= portraitRatio)
        XCTAssertTrue(RectangleFilter.visionMaxAspectRatio >= landscapeRatio)
    }

    func testVisionBoundsAreWiderThanEdgeFilter() {
        // Vision bounds must be wider than the edge-based filter because
        // bounding-box aspect ratios distort more than edge ratios for rotated cards.
        let edgeLower = Float(RectangleFilter.targetAspectRatio * (1 - RectangleFilter.scanAspectRatioTolerance))
        XCTAssertTrue(RectangleFilter.visionMinAspectRatio < edgeLower)
    }

    // MARK: - Helpers

    /// Creates a VNRectangleObservation with axis-aligned corners matching the bounding box.
    private func makeObservation(box: CGRect, confidence: Float) -> VNRectangleObservation {
        makeRectangleObservation(box: box, confidence: confidence)
    }
}
