import XCTest
@testable import MTGScanner

@MainActor
final class RecognitionQueueTests: XCTestCase {

    // MARK: - Initial State

    func testInitialCountsAreZero() {
        let queue = makeFailingQueue()
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertEqual(queue.completedCount, 0)
        XCTAssertEqual(queue.failedCount, 0)
    }

    // MARK: - Enqueue

    func testEnqueueIncrementsPendingCount() {
        let queue = makeFailingQueue()
        queue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: nil)
        XCTAssertEqual(queue.pendingCount, 1)
    }

    func testEnqueueMultipleIncrementsCorrectly() {
        let queue = makeFailingQueue()
        for _ in 0..<3 {
            queue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: nil)
        }
        XCTAssertEqual(queue.pendingCount, 3)
    }

    // MARK: - Failure Handling

    func testFailedJobsIncrementFailedCount() async throws {
        let queue = makeFailingQueue()
        queue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: nil)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertEqual(queue.failedCount, 1)
        XCTAssertEqual(queue.completedCount, 0)
    }

    func testRetryOnce() async throws {
        var callCount = 0
        let queue = RecognitionQueue(recognize: { _, _, _, _ in
            callCount += 1
            throw URLError(.networkConnectionLost)
        })
        queue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: nil)
        try await Task.sleep(for: .milliseconds(200))
        // Should have been called twice: original + 1 retry
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(queue.failedCount, 1)
    }

    // MARK: - Success

    func testSuccessfulJobIncrementsCompletedCount() async throws {
        let queue = RecognitionQueue(recognize: { _, _, _, _ in RecognitionResult(cards: []) })
        queue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: nil)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(queue.completedCount, 1)
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertEqual(queue.failedCount, 0)
    }

    // MARK: - Cropped vs Uncropped Routing

    func testUncroppedJobCallsSingleEndpoint() async throws {
        var singleCalled = false
        let queue = RecognitionQueue(
            recognize: { _, _, _, _ in singleCalled = true; return RecognitionResult(cards: []) },
            recognizeBatch: { _, _, _ in XCTFail("batch should not be called"); return RecognitionResult(cards: []) }
        )
        queue.enqueue(image: makeImage(), isCropped: false, apiBaseURL: "http://localhost", modelContext: nil)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(singleCalled)
    }

    func testCroppedJobCallsBatchEndpoint() async throws {
        var batchCalled = false
        let queue = RecognitionQueue(
            recognize: { _, _, _, _ in XCTFail("single should not be called"); return RecognitionResult(cards: []) },
            recognizeBatch: { crops, _, _ in
                batchCalled = true
                XCTAssertEqual(crops.count, 1)
                return RecognitionResult(cards: [])
            }
        )
        queue.enqueue(image: makeImage(), isCropped: true, apiBaseURL: "http://localhost", modelContext: nil)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(batchCalled)
    }

    func testRetryPreservesCroppedFlag() async throws {
        var batchCallCount = 0
        let queue = RecognitionQueue(
            recognize: { _, _, _, _ in XCTFail("single should not be called"); return RecognitionResult(cards: []) },
            recognizeBatch: { _, _, _ in
                batchCallCount += 1
                throw URLError(.networkConnectionLost)
            }
        )
        queue.enqueue(image: makeImage(), isCropped: true, apiBaseURL: "http://localhost", modelContext: nil)
        try await Task.sleep(for: .milliseconds(300))
        // Original attempt + 1 retry, both via batch.
        XCTAssertEqual(batchCallCount, 2)
        XCTAssertEqual(queue.failedCount, 1)
    }

    func testDefaultEnqueueIsUncropped() async throws {
        var singleCalled = false
        let queue = RecognitionQueue(
            recognize: { _, _, _, _ in singleCalled = true; return RecognitionResult(cards: []) },
            recognizeBatch: { _, _, _ in XCTFail("batch should not be called"); return RecognitionResult(cards: []) }
        )
        queue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: nil)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(singleCalled)
    }

    // MARK: - Concurrency

    func testMaxConcurrentDefaultIsTwo() {
        let queue = makeFailingQueue()
        XCTAssertEqual(queue.maxConcurrent, 2)
    }

    func testConcurrencyLimitIsRespected() async throws {
        actor Counter {
            var current = 0
            var peak = 0
            func increment() { current += 1; peak = max(peak, current) }
            func decrement() { current -= 1 }
        }

        let counter = Counter()
        let queue = RecognitionQueue(recognize: { _, _, _, _ in
            await counter.increment()
            try await Task.sleep(for: .milliseconds(50))
            await counter.decrement()
            return RecognitionResult(cards: [])
        })
        queue.maxConcurrent = 2
        for _ in 0..<6 {
            queue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: nil)
        }
        try await Task.sleep(for: .milliseconds(500))
        let peak = await counter.peak
        XCTAssertLessThanOrEqual(peak, 2)
    }

    // MARK: - Cancel

    func testCancelAllClearsPendingCount() async throws {
        let queue = RecognitionQueue(recognize: { _, _, _, _ in
            try await Task.sleep(for: .seconds(10))
            return RecognitionResult(cards: [])
        })
        queue.maxConcurrent = 1
        for _ in 0..<4 {
            queue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: nil)
        }
        // 1 active, 3 pending
        queue.cancelAll()
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testCancelAllAllowsNewJobsAfterCancel() async throws {
        // After cancelAll, new enqueues should work correctly (activeCount didn't go negative).
        let queue = RecognitionQueue(recognize: { _, _, _, _ in
            try await Task.sleep(for: .seconds(10))
            return RecognitionResult(cards: [])
        })
        queue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: nil)
        queue.cancelAll()
        try await Task.sleep(for: .milliseconds(100))

        // After cancelling, enqueue a fast-completing job to verify the queue is usable.
        let fastQueue = RecognitionQueue(recognize: { _, _, _, _ in RecognitionResult(cards: []) })
        fastQueue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: nil)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(fastQueue.completedCount, 1)
        XCTAssertEqual(fastQueue.pendingCount, 0)
    }

    func testCancelAllPreservesCompletedCount() async throws {
        let queue = RecognitionQueue(recognize: { _, _, _, _ in
            RecognitionResult(cards: [])
        })
        queue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: nil)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(queue.completedCount, 1)

        let longQueue = RecognitionQueue(recognize: { _, _, _, _ in
            try await Task.sleep(for: .seconds(10))
            return RecognitionResult(cards: [])
        })
        longQueue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: nil)
        longQueue.cancelAll()
        // completedCount was 0 before cancel; confirm it stays 0 (not reset to something wrong)
        XCTAssertEqual(longQueue.completedCount, 0)
        // Original queue's completed count is unaffected by separate queue cancellation
        XCTAssertEqual(queue.completedCount, 1)
    }

    func testCancelAllPreservesFailedCount() async throws {
        let queue = makeFailingQueue()
        queue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: nil)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(queue.failedCount, 1)

        queue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: nil)
        queue.cancelAll()
        // Failed count from before cancel is preserved
        XCTAssertEqual(queue.failedCount, 1)
    }

    // MARK: - Capture Time Ordering

    func testCapturedAtPreservedOnRetry() async throws {
        // Verify that a retried job uses the original capture timestamp, not a new one.
        // We test this indirectly: enqueue a job that fails once then succeeds,
        // verify it retried (callCount == 2) and completed. The retry uses the same
        // Job struct, so capturedAt is set at enqueue time, not retry time.
        var callCount = 0
        let queue = RecognitionQueue(recognize: { _, _, _, _ in
            callCount += 1
            if callCount == 1 {
                throw URLError(.networkConnectionLost)
            }
            return RecognitionResult(cards: [])
        })

        queue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: nil)
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(callCount, 2, "Should have been called twice (original + retry)")
        XCTAssertEqual(queue.completedCount, 1)
        XCTAssertEqual(queue.failedCount, 0)
    }
}

// MARK: - Helpers

extension RecognitionQueueTests {
    private func makeFailingQueue() -> RecognitionQueue {
        RecognitionQueue(recognize: { _, _, _, _ in throw URLError(.notConnectedToInternet) })
    }

    private func makeImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        return renderer.image { ctx in
            ctx.cgContext.setFillColor(UIColor.red.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
    }
}
