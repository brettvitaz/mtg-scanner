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

    func testInitialFocusConfigurationFailureRetriesUnchangedCenter() {
        let manager = CameraSessionManager()
        manager.sessionQueue.sync {
            let center = CGPoint(x: 0.5, y: 0.5)
            var attempts = 0
            XCTAssertFalse(manager.prepareFocus(at: center) {
                attempts += 1
                return false
            })
            XCTAssertEqual(attempts, 1)
            XCTAssertTrue(manager.prepareFocus(at: center) {
                attempts += 1
                return true
            })
            XCTAssertEqual(attempts, 2)
            XCTAssertTrue(manager.prepareFocus(at: center) {
                XCTFail("Prepared focus at an unchanged target should be reused")
                return false
            })
        }
    }

    func testFailedRetargetPreservesPreparedPointAndRetriesNewTarget() {
        let manager = CameraSessionManager()
        manager.sessionQueue.sync {
            let center = CGPoint(x: 0.5, y: 0.5)
            let target = CGPoint(x: 0.2, y: 0.7)
            XCTAssertTrue(manager.prepareFocus(at: center) { true })
            XCTAssertFalse(manager.prepareFocus(at: target) { false })
            XCTAssertTrue(manager.prepareFocus(at: center) {
                XCTFail("A failed retarget must preserve the previously configured point")
                return false
            })
            var didRetry = false
            XCTAssertTrue(manager.prepareFocus(at: target) {
                didRetry = true
                return true
            })
            XCTAssertTrue(didRetry)
        }
    }

    func testPreferredBackCameraTypesKeepPhysicalWideFirst() {
        XCTAssertEqual(
            CameraSessionManager.preferredBackCameraTypes,
            [
                .builtInWideAngleCamera,
                .builtInDualCamera,
                .builtInDualWideCamera,
                .builtInTripleCamera
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

    func testFocusFailureResolvesOnceAndReleasesCaptureLock() throws {
        let manager = makeReadyManager()
        let failed = expectation(description: "Focus configuration failure completes capture")
        failed.assertForOverFulfill = true
        manager.captureFocusedPhoto(focusPoint: CGPoint(x: 0.2, y: 0.7)) { result in
            guard case .failure(.focusConfigurationFailed) = result else {
                return XCTFail("Expected focus configuration failure")
            }
            failed.fulfill()
        }
        try manager.sessionQueue.sync {
            let handler = try XCTUnwrap(manager.activeHandlerForTesting() as? PhotoCaptureHandler)
            handler.fail(.focusConfigurationFailed)
            handler.fail(.focusConfigurationFailed)
            XCTAssertFalse(manager.isCaptureInFlightForTesting())
            XCTAssertNil(manager.activeHandlerForTesting())
        }
        wait(for: [failed], timeout: 1)
        manager.stop()
    }

    func testShutDownCancelsOutstandingCaptureAndDisconnectsFrames() {
        let manager = makeReadyManager()
        let cancelled = expectation(description: "Shutdown resolves capture")
        manager.sessionQueue.sync { manager.onFrame = { _ in XCTFail("Old camera delivered a frame") } }
        manager.captureFocusedPhoto(focusPoint: nil) { result in
            guard case .failure(.unavailable) = result else { return XCTFail("Expected cancelled capture") }
            cancelled.fulfill()
        }
        manager.shutDown()
        manager.sessionQueue.sync {
            XCTAssertNil(manager.onFrame)
            XCTAssertFalse(manager.isSessionReady)
            XCTAssertFalse(manager.isCaptureInFlightForTesting())
        }
        wait(for: [cancelled], timeout: 1)
    }

    // MARK: - Session not ready

    func testCaptureBeforeSessionReadyFastFailsWithFailure() {
        let manager = CameraSessionManager()
        let exp = expectation(description: "capture fast-fails when session not ready")
        nonisolated(unsafe) var receivedFailure = false

        manager.captureFocusedPhoto(focusPoint: nil) { data in
            receivedFailure = (try? data.get()) == nil
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertTrue(receivedFailure, "Capture before session is ready must receive a failure")
    }

    // MARK: - Duplicate capture requests

    func testSecondCaptureWhileInFlightFastFailsWithFailure() {
        let manager = makeReadyManager()
        nonisolated(unsafe) var firstCallbackFired = false
        nonisolated(unsafe) var secondReceivedFailure = false

        // First capture: accepted, stays in-flight (no hardware to complete it).
        manager.captureFocusedPhoto(focusPoint: nil) { _ in firstCallbackFired = true }
        // Flush so isCaptureInFlight is set before the second enqueue.
        manager.sessionQueue.sync {}

        // Second capture: must be fast-failed synchronously on the session queue.
        let exp = expectation(description: "second capture fast-fails")
        manager.captureFocusedPhoto(focusPoint: nil) { data in
            secondReceivedFailure = (try? data.get()) == nil
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertFalse(firstCallbackFired, "First capture completion must not be called by the fast-fail path")
        XCTAssertTrue(secondReceivedFailure, "Second capture while in-flight must receive a failure")

        manager.stop()
    }

    // MARK: - stop() drains in-flight completion

    func testStopResolvesInFlightCompletionWithFailure() {
        let manager = makeReadyManager()
        let exp = expectation(description: "completion resolved with a failure by stop")
        nonisolated(unsafe) var receivedFailure = false

        manager.captureFocusedPhoto(focusPoint: nil) { data in
            receivedFailure = (try? data.get()) == nil
            exp.fulfill()
        }
        manager.stop()

        wait(for: [exp], timeout: 1.0)
        XCTAssertTrue(receivedFailure, "stop() must resolve pending completion with a failure")
    }

    // MARK: - isCaptureInFlight cleared after stop()

    func testStopClearsInFlightSoSubsequentCaptureIsAccepted() {
        let manager = makeReadyManager()
        let exp1 = expectation(description: "first capture drained by stop")

        manager.captureFocusedPhoto(focusPoint: nil) { _ in exp1.fulfill() }
        manager.stop()
        wait(for: [exp1], timeout: 1.0)

        // Flush: all enqueued work from stop() has finished.
        // Re-arm isSessionReady since stop() clears it.
        manager.sessionQueue.sync { manager.isSessionReady = true }

        // isCaptureInFlight must now be false. Issue a second capture and verify
        // it is accepted (not fast-failed) by checking it stays pending after the
        // session queue drains — only stop() can resolve it, not the fast-fail path.
        nonisolated(unsafe) var secondCallbackFired = false
        manager.captureFocusedPhoto(focusPoint: nil) { _ in secondCallbackFired = true }

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

    func testCancelledHandlerOnDoneDoesNotClearNewerCapture() {
        // Simulate: capture A started, stop() cancels it, capture B starts, then A's stale
        // onDone fires. captureDidFinish(handler:) must guard on handler identity, leaving B intact.
        let manager = makeReadyManager()

        // Phase 1: start A, grab its handler, cancel A, re-arm, start B.
        let exp1 = expectation(description: "capture A drained by stop")
        manager.captureFocusedPhoto(focusPoint: nil) { _ in exp1.fulfill() }
        let handlerA = captureActiveHandler(from: manager)
        manager.stop()
        wait(for: [exp1], timeout: 1.0)
        manager.sessionQueue.sync { manager.isSessionReady = true }

        // Phase 2: start B, verify stale-A completion doesn't disturb it.
        let exp2 = expectation(description: "capture B drained by second stop")
        nonisolated(unsafe) var captureBReceivedFailure = false
        manager.captureFocusedPhoto(focusPoint: nil) { data in
            captureBReceivedFailure = (try? data.get()) == nil
            exp2.fulfill()
        }
        manager.sessionQueue.sync {}
        let staleResult = fireStaleHandler(handlerA, on: manager)

        XCTAssertNotNil(staleResult.handlerB, "Capture B must be in-flight")
        XCTAssertFalse(handlerA === staleResult.handlerB, "Handler A and B must be distinct objects")
        XCTAssertTrue(staleResult.guardHeld, "Stale handler must not clear the newer active handler")
        XCTAssertTrue(staleResult.inFlight, "Stale handler must not clear in-flight state for capture B")

        // Phase 3: cancel B via stop(), verify its completion fires.
        manager.stop()
        manager.sessionQueue.sync { manager.isSessionReady = true }
        wait(for: [exp2], timeout: 1.0)
        XCTAssertTrue(captureBReceivedFailure, "stop() must resolve capture B with a failure")

        // Phase 4: after two stops, a third capture must be accepted.
        let exp3 = expectation(description: "third capture drained by stop")
        nonisolated(unsafe) var thirdFired = false
        manager.captureFocusedPhoto(focusPoint: nil) { _ in thirdFired = true; exp3.fulfill() }
        manager.stop()
        wait(for: [exp3], timeout: 1.0)
        XCTAssertTrue(thirdFired, "Third capture after two stops must be accepted and resolved")
    }

    // MARK: - Stale-handler helpers

    private func captureActiveHandler(from manager: CameraSessionManager) -> AnyObject? {
        var handler: AnyObject?
        manager.sessionQueue.sync { handler = manager.activeHandlerForTesting() }
        return handler
    }

    private struct StaleFireResult {
        let handlerB: AnyObject?
        let guardHeld: Bool
        let inFlight: Bool
    }

    /// Fires `staleHandler`'s onDone on the session queue and returns the resulting state.
    private func fireStaleHandler(
        _ staleHandler: AnyObject?,
        on manager: CameraSessionManager
    ) -> StaleFireResult {
        nonisolated(unsafe) var handlerB: AnyObject?
        nonisolated(unsafe) var guardHeld = false
        nonisolated(unsafe) var inFlight = false
        manager.sessionQueue.sync {
            handlerB = manager.activeHandlerForTesting()
            manager.finishCaptureForTesting(handler: staleHandler)
            guardHeld = (manager.activeHandlerForTesting() === handlerB)
            inFlight = manager.isCaptureInFlightForTesting()
        }
        return StaleFireResult(handlerB: handlerB, guardHeld: guardHeld, inFlight: inFlight)
    }
}
