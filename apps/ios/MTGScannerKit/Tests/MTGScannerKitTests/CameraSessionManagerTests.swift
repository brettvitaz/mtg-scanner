import XCTest
@testable import MTGScannerKit

final class CameraSessionManagerTests: XCTestCase {

    // MARK: - Duplicate capture requests

    func testSecondCaptureWhileInFlightReturnsNilImmediately() async {
        let manager = CameraSessionManager()
        nonisolated(unsafe) var firstResult: Data?? = .none
        nonisolated(unsafe) var secondResult: Data?? = .none

        manager.capturePhoto { data in firstResult = data }

        await Task.yield()
        // Flush sessionQueue: by the time a second async block runs, the first has set isCaptureInFlight
        let exp = expectation(description: "second capture fast-fails")
        manager.capturePhoto { data in
            secondResult = data
            exp.fulfill()
        }
        await fulfillment(of: [exp], timeout: 1.0)

        // Second caller must receive nil, not block indefinitely
        XCTAssertEqual(secondResult as? Data?, Optional<Data>.none)
    }

    // MARK: - stop() drains in-flight completion

    func testStopDuringAutofocusDelayCallsCompletionWithNil() async {
        let manager = CameraSessionManager()
        let exp = expectation(description: "completion called after stop")
        nonisolated(unsafe) var receivedData: Data?? = .some(.some(Data()))

        manager.capturePhoto { data in
            receivedData = data
            exp.fulfill()
        }

        // stop() before the 300 ms delay fires
        manager.stop()

        await fulfillment(of: [exp], timeout: 1.0)
        XCTAssertEqual(receivedData as? Data?, Optional<Data>.none)
    }

    // MARK: - Capture accepted again after stop()

    func testCaptureAcceptedAfterStopClearsInFlightFlag() async {
        let manager = CameraSessionManager()
        let exp1 = expectation(description: "first completion called")
        let exp2 = expectation(description: "second capture accepted")
        nonisolated(unsafe) var secondWasAccepted = false

        manager.capturePhoto { _ in exp1.fulfill() }
        manager.stop()
        await fulfillment(of: [exp1], timeout: 1.0)

        // After stop drains the flag, a new capture must be accepted (not fast-failed)
        manager.capturePhoto { _ in
            secondWasAccepted = true
            exp2.fulfill()
        }
        // stop() again so the second capture also resolves (don't need hardware)
        manager.stop()
        await fulfillment(of: [exp2], timeout: 1.0)

        XCTAssertTrue(secondWasAccepted)
    }
}
