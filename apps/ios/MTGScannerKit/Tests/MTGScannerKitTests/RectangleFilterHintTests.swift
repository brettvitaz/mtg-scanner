import XCTest
import Vision
@testable import MTGScannerKit

final class RectangleFilterHintTests: XCTestCase {

    private let cropFilter = RectangleFilter(configuration: .crop)

    func testCropFilterPrefersContainedSingleCardCandidate() {
        let outer = makeObservation(
            box: CGRect(x: 0.06, y: 0.06, width: 0.42, height: 0.59),
            confidence: 0.95
        )
        let inner = makeObservation(
            box: CGRect(x: 0.13, y: 0.16, width: 0.28, height: 0.39),
            confidence: 0.75
        )

        let result = cropFilter.filter([outer, inner], isLandscape: false)

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first === inner)
    }

    func testCropRankPrefersHintSizedCandidateOverLargerContainer() {
        let outer = makeObservation(
            box: CGRect(x: 0.06, y: 0.06, width: 0.42, height: 0.59),
            confidence: 0.95
        )
        let inner = makeObservation(
            box: CGRect(x: 0.13, y: 0.16, width: 0.28, height: 0.39),
            confidence: 0.75
        )
        let hint = CGRect(x: 0.13, y: 0.16, width: 0.28, height: 0.39)

        let result = cropFilter.rank(
            [outer, inner],
            isLandscape: false,
            visionHint: hint,
            preferSingle: true
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first === inner)
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

    func testRankPrefersRectangleSupportedByYoloHint() {
        let hinted = makeObservation(
            box: CGRect(x: 0.10, y: 0.10, width: 0.28, height: 0.40),
            confidence: 0.6
        )
        let unsupported = makeObservation(
            box: CGRect(x: 0.60, y: 0.10, width: 0.28, height: 0.40),
            confidence: 0.95
        )
        let hint = CGRect(x: 0.10, y: 0.10, width: 0.28, height: 0.40)

        let result = cropFilter.rank(
            [unsupported, hinted],
            isLandscape: false,
            visionHint: hint,
            preferSingle: true
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first === hinted)
    }

    func testHintedRankRejectsTextBoxSizedCandidateAgainstFullCardHint() {
        let fullCard = makeObservation(
            box: CGRect(x: 0.20, y: 0.20, width: 0.30, height: 0.42),
            confidence: 0.65
        )
        let textBox = makeObservation(
            box: CGRect(x: 0.24, y: 0.24, width: 0.18, height: 0.25),
            confidence: 0.98
        )
        let hint = CGRect(x: 0.20, y: 0.20, width: 0.30, height: 0.42)

        let result = cropFilter.rank(
            [textBox, fullCard],
            isLandscape: false,
            visionHint: hint,
            preferSingle: true
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first === fullCard)
    }

    func testHintedRankAcceptsLowerConfidenceFullCardCandidate() {
        let fullCard = makeObservation(
            box: CGRect(x: 0.20, y: 0.20, width: 0.30, height: 0.42),
            confidence: 0.55
        )
        let unsupported = makeObservation(
            box: CGRect(x: 0.60, y: 0.20, width: 0.30, height: 0.42),
            confidence: 0.98
        )
        let hint = CGRect(x: 0.20, y: 0.20, width: 0.30, height: 0.42)

        let result = cropFilter.rank(
            [unsupported, fullCard],
            isLandscape: false,
            visionHint: hint,
            preferSingle: true
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first === fullCard)
    }

    func testNoHintCropRankingStillAllowsContainedCandidate() {
        let outer = makeObservation(
            box: CGRect(x: 0.06, y: 0.06, width: 0.42, height: 0.59),
            confidence: 0.95
        )
        let inner = makeObservation(
            box: CGRect(x: 0.13, y: 0.16, width: 0.28, height: 0.39),
            confidence: 0.75
        )

        let result = cropFilter.rank(
            [outer, inner],
            isLandscape: false,
            visionHint: nil,
            preferSingle: true
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first === inner)
    }

    private func makeObservation(box: CGRect, confidence: Float) -> VNRectangleObservation {
        makeRectangleObservation(box: box, confidence: confidence)
    }
}
