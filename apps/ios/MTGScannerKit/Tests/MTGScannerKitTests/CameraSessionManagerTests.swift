import CoreMedia
import XCTest
@testable import MTGScannerKit

/// Tests for CameraSessionManager's capture serialization logic.
///
/// These tests use `manager.sessionQueue.sync {}` as a reliable flush point:
/// because sessionQueue is serial, a sync barrier guarantees all previously
/// enqueued work has completed before assertions run.
///
/// No real camera hardware is available in tests. `suppressCaptureForTesting`
/// keeps the manager from issuing a real `AVCapturePhotoOutput` request, while
/// `isSessionReady` is set directly so the readiness guard passes without
/// requiring a real running session.
/// These tests cover the guard logic and state-machine bookkeeping, not
/// hardware behavior.
final class CameraSessionManagerTests: XCTestCase {

    // MARK: - Helpers

    /// Returns a manager with `isSessionReady` set to `true` on its session queue,
    /// simulating a session that has been configured and started.
    private func makeReadyManager() -> CameraSessionManager {
        let manager = CameraSessionManager()
        manager.sessionQueue.sync {
            manager.isSessionReady = true
            manager.suppressCaptureForTesting = true
        }
        return manager
    }

    // MARK: - Camera/photo configuration helpers

    func testPreferredBackCameraTypesPreferVirtualCloseRangeCapableDevices() {
        XCTAssertEqual(
            CameraSessionManager.preferredBackCameraTypes,
            [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera
            ]
        )
    }

    func testLargestPhotoDimensionsUsesPixelAreaInsteadOfArrayOrder() {
        let dimensions = [
            CMVideoDimensions(width: 4032, height: 2268),
            CMVideoDimensions(width: 3840, height: 2160),
            CMVideoDimensions(width: 4032, height: 3024),
            CMVideoDimensions(width: 1920, height: 1080)
        ]

        let largest = CameraSessionManager.largestPhotoDimensions(in: dimensions)

        XCTAssertEqual(largest?.width, 4032)
        XCTAssertEqual(largest?.height, 3024)
    }

    // MARK: - Session not ready

    func testCaptureBeforeSessionReadyFastFailsWithNil() {
        let manager = CameraSessionManager()
        let exp = expectation(description: "capture fast-fails when session not ready")
        nonisolated(unsafe) var receivedNil = false

        manager.capturePhoto { data in
            receivedNil = (data == nil)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(receivedNil, "Capture before session is ready must receive nil")
    }

    // MARK: - Duplicate capture requests

    func testSecondCaptureWhileInFlightFastFailsWithNil() {
        let manager = makeReadyManager()
        nonisolated(unsafe) var firstCallbackFired = false
        nonisolated(unsafe) var secondReceivedNil = false

        // First capture: accepted, stays in-flight (no hardware to complete it).
        manager.capturePhoto { _ in firstCallbackFired = true }
        // Flush so isCaptureInFlight is set before the second enqueue.
        manager.sessionQueue.sync {}

        // Second capture: must be fast-failed synchronously on the session queue.
        let exp = expectation(description: "second capture fast-fails")
        manager.capturePhoto { data in
            secondReceivedNil = (data == nil)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertFalse(firstCallbackFired, "First capture completion must not be called by the fast-fail path")
        XCTAssertTrue(secondReceivedNil, "Second capture while in-flight must receive nil")

        manager.stop()
    }

    // MARK: - stop() drains in-flight completion

    func testStopResolvesInFlightCompletionWithNil() {
        let manager = makeReadyManager()
        let exp = expectation(description: "completion resolved with nil by stop")
        nonisolated(unsafe) var receivedNil = false

        manager.capturePhoto { data in
            receivedNil = (data == nil)
            exp.fulfill()
        }
        manager.stop()

        wait(for: [exp], timeout: 1.0)
        XCTAssertTrue(receivedNil, "stop() must resolve pending completion with nil")
    }

    // MARK: - isCaptureInFlight cleared after stop()

    func testStopClearsInFlightSoSubsequentCaptureIsAccepted() {
        let manager = makeReadyManager()
        let exp1 = expectation(description: "first capture drained by stop")

        manager.capturePhoto { _ in exp1.fulfill() }
        manager.stop()
        wait(for: [exp1], timeout: 1.0)

        // Flush: all enqueued work from stop() has finished.
        // Re-arm isSessionReady since stop() clears it.
        manager.sessionQueue.sync { manager.isSessionReady = true }

        // isCaptureInFlight must now be false. Issue a second capture and verify
        // it is accepted (not fast-failed) by checking it stays pending after the
        // session queue drains — only stop() can resolve it, not the fast-fail path.
        nonisolated(unsafe) var secondCallbackFired = false
        manager.capturePhoto { _ in secondCallbackFired = true }

        // Flush: if the second capture was fast-failed, its completion already ran.
        manager.sessionQueue.sync {}
        // A main-queue flush ensures any DispatchQueue.main.async from fast-fail has run.
        let mainFlush = expectation(description: "main queue flushed")
        DispatchQueue.main.async { mainFlush.fulfill() }
        wait(for: [mainFlush], timeout: 1.0)

        XCTAssertFalse(secondCallbackFired, "Second capture must be accepted (pending), not fast-failed")

        manager.stop()
    }

    // MARK: - Stale handler cannot clear active capture state

    // swiftlint:disable:next function_body_length
    func testCancelledHandlerOnDoneDoesNotClearNewerCapture() {
        // Simulate: capture A started, stop() cancels it (increments generation),
        // capture B starts. Then A's onDone fires (as would happen if a stale
        // didFinishProcessingPhoto arrived after re-entry).
        // captureDidFinish(handler:) must guard on handler identity and leave B intact.
        let manager = makeReadyManager()
        let exp1 = expectation(description: "capture A drained by stop")

        // Capture A
        manager.capturePhoto { _ in exp1.fulfill() }
        // Grab handler A before stop() clears it.
        var handlerA: AnyObject?
        manager.sessionQueue.sync { handlerA = manager.activeHandlerForTesting() }
        manager.stop()
        wait(for: [exp1], timeout: 1.0)
        // Re-arm isSessionReady since stop() clears it.
        manager.sessionQueue.sync { manager.isSessionReady = true }

        // Capture B
        let exp2 = expectation(description: "capture B drained by second stop")
        nonisolated(unsafe) var captureBReceivedNil = false
        manager.capturePhoto { data in
            captureBReceivedNil = (data == nil)
            exp2.fulfill()
        }
        manager.sessionQueue.sync {}
        var handlerB: AnyObject?
        nonisolated(unsafe) var staleHandlerDidNotClearActiveCapture = false
        nonisolated(unsafe) var captureBStillInFlight = false
        manager.sessionQueue.sync {
            handlerB = manager.activeHandlerForTesting()
            manager.finishCaptureForTesting(handler: handlerA)
            staleHandlerDidNotClearActiveCapture = (manager.activeHandlerForTesting() === handlerB)
            captureBStillInFlight = manager.isCaptureInFlightForTesting()
        }

        XCTAssertNotNil(handlerB, "Capture B must be in-flight")
        XCTAssertFalse(handlerA === handlerB, "Handler A and B must be distinct objects")
        XCTAssertTrue(
            staleHandlerDidNotClearActiveCapture,
            "Stale handler completion must not clear the newer active handler"
        )
        XCTAssertTrue(
            captureBStillInFlight,
            "Stale handler completion must not clear in-flight state for capture B"
        )

        // Explicitly cancel B and verify its completion still resolves normally.
        manager.stop()
        manager.sessionQueue.sync { manager.isSessionReady = true }
        wait(for: [exp2], timeout: 1.0)
        XCTAssertTrue(
            captureBReceivedNil,
            "stop() must still resolve the current capture after a stale completion attempt"
        )

        // After cancelling B, a third capture should be accepted.
        let exp3 = expectation(description: "third capture drained by stop")
        nonisolated(unsafe) var thirdCallbackFired = false
        manager.capturePhoto { _ in
            thirdCallbackFired = true
            exp3.fulfill()
        }
        manager.stop()
        wait(for: [exp3], timeout: 1.0)

        XCTAssertTrue(thirdCallbackFired, "Third capture after two stops must be accepted and resolved")
    }
}
