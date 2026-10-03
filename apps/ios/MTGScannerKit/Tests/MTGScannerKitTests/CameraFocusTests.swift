import Foundation
import XCTest
@testable import MTGScannerKit

final class CameraFocusTests: XCTestCase {
    func testYOLOPointUsesNativeTopLeftCoordinates() {
        let point = CameraFocus.point(fromYOLOBox: CGRect(x: 0.1, y: 0.6, width: 0.2, height: 0.3))
        XCTAssertEqual(point.x, 0.2, accuracy: 0.001)
        XCTAssertEqual(point.y, 0.75, accuracy: 0.001)
    }

    func testInvalidOrMissingBoxesFallBackToCenter() {
        let boxes: [CGRect?] = [nil, .zero, CGRect(x: -0.1, y: 0.2, width: 0.3, height: 0.4),
                                CGRect(x: 0.9, y: 0.2, width: 0.3, height: 0.4),
                                CGRect(x: CGFloat.nan, y: 0.2, width: 0.3, height: 0.4)]
        for box in boxes {
            XCTAssertEqual(CameraFocus.point(fromYOLOBox: box), CGPoint(x: 0.5, y: 0.5))
        }
    }

    func testInitialIdleCannotReleaseShutterImmediatelyAfterRetargeting() {
        var state = FocusSettlingState(startedAt: 0)
        XCTAssertEqual(state.evaluate(isAdjusting: false, at: 0, deadline: 0.5), .waiting)
        XCTAssertEqual(state.evaluate(isAdjusting: false, at: 0.09, deadline: 0.5), .waiting)
        XCTAssertEqual(state.evaluate(isAdjusting: false, at: 0.1, deadline: 0.5), .settled)
    }

    func testPreparedFocusCapturesWithoutAddingAnotherWait() {
        var state = FocusSettlingState(startedAt: 0)
        state.record(isAdjusting: true, at: 0.02)
        state.record(isAdjusting: false, at: 0.1)
        XCTAssertEqual(state.evaluate(isAdjusting: false, at: 2, deadline: 2.5), .settled)
    }

    func testDelayedAdjustmentMustFinishAndRemainStable() {
        var state = FocusSettlingState(startedAt: 0)
        XCTAssertEqual(state.evaluate(isAdjusting: false, at: 0, deadline: 0.5), .waiting)
        XCTAssertEqual(state.evaluate(isAdjusting: true, at: 0.09, deadline: 0.5), .waiting)
        XCTAssertEqual(state.evaluate(isAdjusting: false, at: 0.2, deadline: 0.5), .waiting)
        XCTAssertEqual(state.evaluate(isAdjusting: false, at: 0.24, deadline: 0.5), .waiting)
        XCTAssertEqual(state.evaluate(isAdjusting: false, at: 0.26, deadline: 0.5), .settled)
    }

    func testObservedAdjustmentBetweenFramesRestartsIdleWindow() {
        var state = FocusSettlingState(startedAt: 0)
        state.record(isAdjusting: false, at: 0)
        state.recordAdjustment()
        XCTAssertEqual(state.evaluate(isAdjusting: false, at: 2, deadline: 2.5), .waiting)
        XCTAssertEqual(state.evaluate(isAdjusting: false, at: 2.06, deadline: 2.5), .settled)
    }

    func testOngoingAdjustmentCapturesAtDeadlineInsteadOfFailing() {
        var state = FocusSettlingState(startedAt: 0)
        XCTAssertEqual(state.evaluate(isAdjusting: true, at: 2, deadline: 2.5), .waiting)
        XCTAssertEqual(state.evaluate(isAdjusting: true, at: 2.49, deadline: 2.5), .waiting)
        XCTAssertEqual(state.evaluate(isAdjusting: true, at: 2.5, deadline: 2.5), .captureAtDeadline)
        XCTAssertEqual(state.evaluate(isAdjusting: false, at: 2.51, deadline: 2.5), .captureAtDeadline)
    }

    func testDetectionJitterDoesNotRestartFocus() {
        XCTAssertFalse(CameraFocus.needsRetargeting(from: CGPoint(x: 0.4, y: 0.5), to: CGPoint(x: 0.41, y: 0.49)))
        XCTAssertTrue(CameraFocus.needsRetargeting(from: CGPoint(x: 0.4, y: 0.5), to: CGPoint(x: 0.45, y: 0.5)))
        XCTAssertTrue(CameraFocus.needsRetargeting(from: CGPoint(x: 0.4, y: 0.5), to: CGPoint(x: 0.4, y: 0.55)))
    }
}
