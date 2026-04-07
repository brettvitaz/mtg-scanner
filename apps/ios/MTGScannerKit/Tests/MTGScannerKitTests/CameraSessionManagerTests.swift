import XCTest
@testable import MTGScannerKit

final class CameraSessionManagerTests: XCTestCase {

    // MARK: - Duplicate capture requests

    func testSecondCaptureWhileInFlightReturnsNilImmediately() async {
        let manager = CameraSessionManager()
        let firstStarted = expectation(description: "first capture enqueued")
        let secondFailed = expectation(description: "second capture fast-fails with nil")
        nonisolated(unsafe) var secondResult: Data?? = .some(.some(Data()))

        // First capture: just marks in-flight; no hardware → completion never fires naturally
        manager.capturePhoto { _ in firstStarted.fulfill() }
        // stop() drains the first so the fast-fail check is observable in isolation
        manager.stop()
        await fulfillment(of: [firstStarted], timeout: 1.0)

        // Reinstall in-flight state for the second test: issue a capture, then immediately
        // issue a second one before stop() can drain the first.
        let manager2 = CameraSessionManager()
        nonisolated(unsafe) var secondReceivedNil = false
        manager2.capturePhoto { _ in }  // first — stays in-flight
        manager2.capturePhoto { data in
            secondReceivedNil = (data == nil)
            secondFailed.fulfill()
        }
        await fulfillment(of: [secondFailed], timeout: 1.0)
        XCTAssertTrue(secondReceivedNil, "Second capture while first is in flight must receive nil")
        manager2.stop()
    }

    // MARK: - stop() drains in-flight completion

    func testStopCallsCompletionWithNilWhenNoCaptureDevice() async {
        // captureDevice is nil on an unconfigured manager, so the focus path is skipped.
        // This verifies that stop() drains the stored completion with nil regardless.
        let manager = CameraSessionManager()
        let exp = expectation(description: "completion called with nil after stop")
        nonisolated(unsafe) var receivedData: Data?? = .some(.some(Data()))

        manager.capturePhoto { data in
            receivedData = data
            exp.fulfill()
        }
        manager.stop()

        await fulfillment(of: [exp], timeout: 1.0)
        XCTAssertNil(receivedData as? Data?, "stop() must resolve pending completion with nil")
    }

    // MARK: - isCaptureInFlight cleared after stop()

    func testCaptureFlagClearedAfterStop() async {
        // After stop() drains an in-flight capture, a subsequent capturePhoto must be
        // accepted (not fast-failed). We verify acceptance by confirming stop() is
        // required to resolve the second request — if it were fast-failed it would
        // have already called the completion with nil before the second stop().
        let manager = CameraSessionManager()
        let exp1 = expectation(description: "first completion drained by first stop")
        let exp2 = expectation(description: "second capture accepted and drained by second stop")
        nonisolated(unsafe) var secondCompletionCalledBeforeSecondStop = false

        manager.capturePhoto { _ in exp1.fulfill() }
        manager.stop()
        await fulfillment(of: [exp1], timeout: 1.0)

        // If isCaptureInFlight is incorrectly stuck true, this would fast-fail
        // synchronously on the session queue, setting the flag before the second stop().
        manager.capturePhoto { _ in
            secondCompletionCalledBeforeSecondStop = true
            exp2.fulfill()
        }

        // Yield to let the session queue process capturePhoto — if it fast-failed, exp2
        // is already fulfilled and secondCompletionCalledBeforeSecondStop is true.
        // If it was accepted, the completion is pending and exp2 is not yet fulfilled.
        await Task.yield()

        // Second capture must still be pending here (not fast-failed)
        XCTAssertFalse(secondCompletionCalledBeforeSecondStop,
                       "Second capture must be accepted (pending), not fast-failed before second stop()")

        manager.stop()
        await fulfillment(of: [exp2], timeout: 1.0)
    }
}
