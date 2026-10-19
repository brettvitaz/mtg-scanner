import XCTest
@testable import MTGScannerKit

final class SceneMotionReferenceTests: XCTestCase {
    func testWarmupLearnsVariationButPreservesNewSceneMotion() {
        var reference = SceneMotionReference(windowSize: 4)
        for samples: [UInt8] in [[10, 20], [13, 25], [11, 24]] {
            _ = reference.observe(samples)
            XCTAssertFalse(reference.isReady)
        }
        _ = reference.observe([12, 22])
        XCTAssertTrue(reference.isReady)
        XCTAssertEqual(reference.observe([12, 24]).motion, 0)
        XCTAssertEqual(reference.observe([100, 120]).motion, 182.0 / 510, accuracy: 0.0001)
    }

    func testCaptureFramesProvideNextBaselineWithoutAnotherWarmup() {
        var reference = SceneMotionReference(windowSize: 4)
        for _ in 0..<4 { _ = reference.observe([10, 20]) }
        reference.beginCapture()
        for samples: [UInt8] in [[198, 199], [202, 201], [199, 202], [201, 198]] {
            _ = reference.observe(samples)
        }
        reference.rearm()
        XCTAssertTrue(reference.isReady)
        XCTAssertEqual(reference.observe([200, 200]).motion, 0)
        XCTAssertGreaterThan(reference.observe([80, 80]).motion, 0.4)
    }
    func testMovementDuringPreparationIsNotLearnedAsNormalNoise() {
        var reference = SceneMotionReference(windowSize: 4)
        for _ in 0..<4 { _ = reference.observe([0, 0]) }
        reference.beginCapture()
        _ = reference.observe([255, 255])
        _ = reference.observe([0, 0])
        _ = reference.observe([255, 255])
        _ = reference.observe([0, 0])
        reference.rearm()
        XCTAssertGreaterThan(reference.observe([255, 255]).motion, 0.9)
    }

    func testRepeatedEmptyRearmingDoesNotExpandNoiseBand() {
        var reference = SceneMotionReference(windowSize: 4)
        for value: UInt8 in [10, 14, 10, 14] { _ = reference.observe([value]) }
        reference.beginCapture()
        for _ in 0..<10 { reference.rearm() }
        XCTAssertGreaterThan(reference.observe([100]).motion, 0.3)
    }

    func testShortPreparationDoesNotAbsorbAnArrival() {
        var reference = SceneMotionReference(windowSize: 4)
        for _ in 0..<4 { _ = reference.observe([0]) }
        reference.beginCapture()
        _ = reference.observe([255])
        _ = reference.observe([0])
        reference.rearm()
        XCTAssertTrue(reference.isReady)
        XCTAssertGreaterThan(reference.observe([255]).motion, 0.9)
    }

    func testStartupMovementCannotCreateAnUnlimitedNoiseBand() {
        var reference = SceneMotionReference(windowSize: 4)
        for value: UInt8 in [0, 255, 0, 255] { _ = reference.observe([value]) }
        XCTAssertFalse(reference.isReady)
        for _ in 0..<4 { _ = reference.observe([128]) }
        XCTAssertTrue(reference.isReady)
        XCTAssertGreaterThan(reference.observe([255]).motion, 0.4)
    }

    func testPreparationBandIsValidatedInsideTheCalibratedRegion() {
        var reference = SceneMotionReference(windowSize: 4)
        let region = Array(0..<10)
        let quiet = [UInt8](repeating: 0, count: 100)
        let changed = [UInt8](repeating: 30, count: 10) + [UInt8](repeating: 0, count: 90)
        for _ in 0..<4 { _ = reference.observe(quiet, within: region) }
        reference.beginCapture()
        for samples in [changed, quiet, changed, quiet] { _ = reference.observe(samples, within: region) }
        reference.rearm()
        XCTAssertGreaterThan(reference.observe(changed, within: region).motion, 0.1)
    }

    func testQuietPreparationDoesNotForgetPreviouslyLearnedVariation() {
        var reference = SceneMotionReference(windowSize: 4)
        for value: UInt8 in [10, 14, 10, 14] { _ = reference.observe([value]) }
        reference.beginCapture()
        for _ in 0..<4 { _ = reference.observe([100]) }
        reference.rearm()
        XCTAssertEqual(reference.observe([102]).motion, 0)
        XCTAssertGreaterThan(reference.observe([200]).motion, 0.3)
    }

    func testCalibrationTransitionValidatesPreparationWithinDestinationRegion() {
        var reference = SceneMotionReference(windowSize: 4)
        let quiet = [UInt8](repeating: 0, count: 100)
        let changed = [UInt8](repeating: 30, count: 10) + [UInt8](repeating: 0, count: 90)
        for _ in 0..<4 { _ = reference.observe(quiet) }
        reference.beginCapture()
        for samples in [changed, quiet, changed, quiet] { _ = reference.observe(samples) }
        reference.rearm(within: Array(0..<10))
        XCTAssertGreaterThan(reference.observe(changed, within: Array(0..<10)).motion, 0.1)
    }

}
