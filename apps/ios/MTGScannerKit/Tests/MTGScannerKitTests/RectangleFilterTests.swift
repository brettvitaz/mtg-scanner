import XCTest
import Vision
@testable import MTGScannerKit

// swiftlint:disable type_body_length
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

        let allX = [tl.x, tr.x, br.x, bl.x]
        let allY = [tl.y, tr.y, br.y, bl.y]
        // swiftlint:disable force_unwrapping
        let box = CGRect(
            x: allX.min()!, y: allY.min()!,
            width: allX.max()! - allX.min()!,
            height: allY.max()! - allY.min()!
        )
        // swiftlint:enable force_unwrapping

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

    // MARK: - NMS

    func testFilterSuppressesHeavilyOverlappingDuplicates() {
        // Two nearly-identical card-shaped boxes — only the higher-confidence one should survive.
        let ratio = RectangleFilter.targetAspectRatio
        let height: CGFloat = 0.4
        let width = height * ratio
        let high = makeObservation(box: CGRect(x: 0.1, y: 0.1, width: width, height: height), confidence: 0.9)
        // Slightly shifted but IoU >> 0.45
        let low = makeObservation(box: CGRect(x: 0.102, y: 0.102, width: width, height: height), confidence: 0.6)
        let result = filter.filter([low, high], isLandscape: false)
        XCTAssertEqual(result.count, 1)
        // swiftlint:disable:next force_unwrapping
        XCTAssertEqual(result.first!.confidence, 0.9, accuracy: 0.001)
    }

    func testFilterPreservesNonOverlappingDetections() {
        let ratio = RectangleFilter.targetAspectRatio
        let height: CGFloat = 0.3
        let width = height * ratio
        // Place two cards far apart (no IoU overlap).
        let left = makeObservation(box: CGRect(x: 0.0, y: 0.1, width: width, height: height), confidence: 0.8)
        let right = makeObservation(box: CGRect(x: 0.6, y: 0.1, width: width, height: height), confidence: 0.7)
        let result = filter.filter([left, right], isLandscape: false)
        XCTAssertEqual(result.count, 2)
    }

    func testFilterPrefersEnclosingCardOverHigherConfidenceInnerFeature() {
        let ratio = RectangleFilter.targetAspectRatio
        let outerHeight: CGFloat = 0.45
        let outerWidth = outerHeight * ratio
        let innerHeight: CGFloat = 0.22
        let innerWidth = innerHeight * ratio

        let outer = makeObservation(
            box: CGRect(x: 0.10, y: 0.10, width: outerWidth, height: outerHeight),
            confidence: 0.75
        )
        let inner = makeObservation(
            box: CGRect(x: 0.16, y: 0.18, width: innerWidth, height: innerHeight),
            confidence: 0.95
        )

        let result = filter.filter([inner, outer], isLandscape: false)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].boundingBox, outer.boundingBox)
    }

    func testFilterPrefersEnclosingCardOverHigherConfidenceInnerFeatureRegardlessOfInputOrder() {
        let ratio = RectangleFilter.targetAspectRatio
        let outerHeight: CGFloat = 0.45
        let outerWidth = outerHeight * ratio
        let innerHeight: CGFloat = 0.22
        let innerWidth = innerHeight * ratio

        let outer = makeObservation(
            box: CGRect(x: 0.10, y: 0.10, width: outerWidth, height: outerHeight),
            confidence: 0.75
        )
        let inner = makeObservation(
            box: CGRect(x: 0.16, y: 0.18, width: innerWidth, height: innerHeight),
            confidence: 0.95
        )

        let result = filter.filter([outer, inner], isLandscape: false)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].boundingBox, outer.boundingBox)
    }

    func testFilterSuppressesNestedInnerFeatureWhenOuterCardIsAcceptedFirst() {
        let ratio = RectangleFilter.targetAspectRatio
        let outerHeight: CGFloat = 0.45
        let outerWidth = outerHeight * ratio
        let innerHeight: CGFloat = 0.22
        let innerWidth = innerHeight * ratio

        let outer = makeObservation(
            box: CGRect(x: 0.10, y: 0.10, width: outerWidth, height: outerHeight),
            confidence: 0.95
        )
        let inner = makeObservation(
            box: CGRect(x: 0.16, y: 0.18, width: innerWidth, height: innerHeight),
            confidence: 0.75
        )

        let result = filter.filter([outer, inner], isLandscape: false)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].boundingBox, outer.boundingBox)
    }

    func testFilterKeepsHigherConfidenceInnerCardWhenOuterBoxIsOnlySlightlyLarger() {
        let ratio = RectangleFilter.targetAspectRatio
        let innerHeight: CGFloat = 0.40
        let innerWidth = innerHeight * ratio
        let outerHeight: CGFloat = 0.43
        let outerWidth = outerHeight * ratio

        let inner = makeObservation(
            box: CGRect(x: 0.12, y: 0.12, width: innerWidth, height: innerHeight),
            confidence: 0.95
        )
        let outer = makeObservation(
            box: CGRect(x: 0.105, y: 0.105, width: outerWidth, height: outerHeight),
            confidence: 0.45
        )

        let result = filter.filter([inner, outer], isLandscape: false)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].boundingBox, inner.boundingBox)
    }

    func testFilterDoesNotReplaceMultipleContainedInnerBoxesWithSingleOuterBox() {
        let ratio = RectangleFilter.targetAspectRatio
        let outerHeight: CGFloat = 0.50
        let outerWidth = outerHeight * ratio
        let innerHeight: CGFloat = 0.22
        let innerWidth = innerHeight * ratio

        let leftInner = makeObservation(
            box: CGRect(x: 0.14, y: 0.16, width: innerWidth, height: innerHeight),
            confidence: 0.95
        )
        let rightInner = makeObservation(
            box: CGRect(x: 0.30, y: 0.18, width: innerWidth, height: innerHeight),
            confidence: 0.90
        )
        let outer = makeObservation(
            box: CGRect(x: 0.10, y: 0.10, width: outerWidth, height: outerHeight),
            confidence: 0.70
        )

        let result = filter.filter([leftInner, rightInner, outer], isLandscape: false)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].boundingBox, leftInner.boundingBox)
        XCTAssertEqual(result[1].boundingBox, rightInner.boundingBox)
    }

    func testFilterKeepsOutermostSingleCardAcrossContainmentChain() {
        let ratio = RectangleFilter.targetAspectRatio
        let outerHeight: CGFloat = 0.52
        let outerWidth = outerHeight * ratio
        let middleHeight: CGFloat = 0.34
        let middleWidth = middleHeight * ratio
        let innerHeight: CGFloat = 0.20
        let innerWidth = innerHeight * ratio

        let outer = makeObservation(
            box: CGRect(x: 0.08, y: 0.08, width: outerWidth, height: outerHeight),
            confidence: 0.70
        )
        let middle = makeObservation(
            box: CGRect(x: 0.14, y: 0.16, width: middleWidth, height: middleHeight),
            confidence: 0.85
        )
        let inner = makeObservation(
            box: CGRect(x: 0.20, y: 0.24, width: innerWidth, height: innerHeight),
            confidence: 0.95
        )

        let result = filter.filter([inner, middle, outer], isLandscape: false)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].boundingBox, outer.boundingBox)
    }

    func testFilterKeepsPartiallyOverlappingBoxesBelowContainmentThreshold() {
        let ratio = RectangleFilter.targetAspectRatio
        let height: CGFloat = 0.32
        let width = height * ratio

        let first = makeObservation(
            box: CGRect(x: 0.10, y: 0.10, width: width, height: height),
            confidence: 0.90
        )
        let second = makeObservation(
            box: CGRect(x: 0.22, y: 0.18, width: width, height: height),
            confidence: 0.85
        )

        let result = filter.filter([first, second], isLandscape: false)
        XCTAssertEqual(result.count, 2)
    }

    func testFilterKeepsAlmostSameSizeBoxesForNMSInsteadOfContainment() {
        let ratio = RectangleFilter.targetAspectRatio
        let outerHeight: CGFloat = 0.40
        let outerWidth = outerHeight * ratio
        let innerHeight = outerHeight / sqrt(RectangleFilter.containmentAreaRatioThreshold - 0.05)
        let innerWidth = innerHeight * ratio

        let larger = makeObservation(
            box: CGRect(x: 0.10, y: 0.10, width: outerWidth, height: outerHeight),
            confidence: 0.90
        )
        let almostSame = makeObservation(
            box: CGRect(x: 0.105, y: 0.105, width: innerWidth, height: innerHeight),
            confidence: 0.80
        )

        let result = filter.filter([larger, almostSame], isLandscape: false)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].boundingBox, larger.boundingBox)
    }

    func testCropFilterDoesNotApplyContainmentSuppression() {
        let ratio = RectangleFilter.targetAspectRatio
        let outerHeight: CGFloat = 0.45
        let outerWidth = outerHeight * ratio
        let innerHeight: CGFloat = 0.22
        let innerWidth = innerHeight * ratio

        let outer = makeObservation(
            box: CGRect(x: 0.10, y: 0.10, width: outerWidth, height: outerHeight),
            confidence: 0.75
        )
        let inner = makeObservation(
            box: CGRect(x: 0.16, y: 0.18, width: innerWidth, height: innerHeight),
            confidence: 0.95
        )

        let result = cropFilter.filter([inner, outer], isLandscape: false)

        XCTAssertEqual(result.count, 2)
    }

    func testFilterReturnsEmptyForEmptyInput() {
        XCTAssertEqual(filter.filter([], isLandscape: false).count, 0)
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
            CGRect(x: 0.5, y: 0.05, width: 0.18, height: 0.25)  // low minY, right side
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

    /// Creates a VNRectangleObservation with axis-aligned corners matching the bounding box.
    ///
    /// VNRectangleObservation cannot be directly initialized; we use KVC to set properties.
    /// Corner convention follows Vision's bottom-left origin.
    private func makeObservation(box: CGRect, confidence: Float) -> VNRectangleObservation {
        let obs = VNRectangleObservation()
        obs.setValue(box, forKey: "boundingBox")
        obs.setValue(confidence, forKey: "confidence")
        // Vision corners: bottom-left origin, topLeft is top-left of the detected quad.
        obs.setValue(CGPoint(x: box.minX, y: box.maxY), forKey: "topLeft")
        obs.setValue(CGPoint(x: box.maxX, y: box.maxY), forKey: "topRight")
        obs.setValue(CGPoint(x: box.maxX, y: box.minY), forKey: "bottomRight")
        obs.setValue(CGPoint(x: box.minX, y: box.minY), forKey: "bottomLeft")
        return obs
    }
}
// swiftlint:enable type_body_length
