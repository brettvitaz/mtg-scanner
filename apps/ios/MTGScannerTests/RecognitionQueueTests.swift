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
        let queue = RecognitionQueue { _, _, _, _ in
            callCount += 1
            throw URLError(.networkConnectionLost)
        }
        queue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: nil)
        try await Task.sleep(for: .milliseconds(200))
        // Should have been called twice: original + 1 retry
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(queue.failedCount, 1)
    }

    // MARK: - Success

    func testSuccessfulJobIncrementsCompletedCount() async throws {
        let queue = RecognitionQueue { _, _, _, _ in RecognitionResult(cards: []) }
        queue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: nil)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(queue.completedCount, 1)
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertEqual(queue.failedCount, 0)
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
        let queue = RecognitionQueue { _, _, _, _ in
            await counter.increment()
            try await Task.sleep(for: .milliseconds(50))
            await counter.decrement()
            return RecognitionResult(cards: [])
        }
        queue.maxConcurrent = 2
        for _ in 0..<6 {
            queue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: nil)
        }
        try await Task.sleep(for: .milliseconds(500))
        let peak = await counter.peak
        XCTAssertLessThanOrEqual(peak, 2)
    }
}

// MARK: - Helpers

extension RecognitionQueueTests {
    private func makeFailingQueue() -> RecognitionQueue {
        RecognitionQueue { _, _, _, _ in throw URLError(.notConnectedToInternet) }
    }

    private func makeImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        return renderer.image { ctx in
            ctx.cgContext.setFillColor(UIColor.red.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
    }
}
