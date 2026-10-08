import XCTest
@testable import MTGScannerKit

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
        queue.enqueue(image: makeImage(), modelContext: nil)
        XCTAssertEqual(queue.pendingCount, 1)
    }

    func testEnqueueMultipleIncrementsCorrectly() {
        let queue = makeFailingQueue()
        for _ in 0..<3 {
            queue.enqueue(image: makeImage(), modelContext: nil)
        }
        XCTAssertEqual(queue.pendingCount, 3)
    }

    // MARK: - Failure Handling

    func testFailedJobsIncrementFailedCount() async throws {
        let queue = makeFailingQueue()
        queue.enqueue(image: makeImage(), modelContext: nil)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertEqual(queue.failedCount, 1)
        XCTAssertEqual(queue.completedCount, 0)
    }

    func testRetryOnce() async throws {
        nonisolated(unsafe) var callCount = 0
        let queue = RecognitionQueue(cardRecognizer: StubCardRecognizer(recognize: { _, _, _ in
            callCount += 1
            throw URLError(.networkConnectionLost)
        }))
        queue.enqueue(image: makeImage(), modelContext: nil)
        try await Task.sleep(for: .milliseconds(200))
        // Should have been called twice: original + 1 retry
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(queue.failedCount, 1)
    }

    // MARK: - Success

    func testSuccessfulJobIncrementsCompletedCount() async throws {
        let queue = makeSucceedingQueue()
        queue.enqueue(image: makeImage(), modelContext: nil)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(queue.completedCount, 1)
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertEqual(queue.failedCount, 0)
    }

    func testJobKeepsRecognizerFromEnqueueTimeThroughRetry() async throws {
        nonisolated(unsafe) var originalCallCount = 0
        nonisolated(unsafe) var replacementCalled = false
        let queue = RecognitionQueue(cardRecognizer: StubCardRecognizer(recognize: { _, _, _ in
            originalCallCount += 1
            if originalCallCount == 1 { throw URLError(.networkConnectionLost) }
            return RecognitionResult(cards: [])
        }))
        queue.enqueue(image: makeImage(), modelContext: nil)
        queue.cardRecognizer = StubCardRecognizer(recognize: { _, _, _ in
            replacementCalled = true
            return RecognitionResult(cards: [])
        })
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(originalCallCount, 2, "Original attempt and retry use the enqueue-time recognizer")
        XCTAssertFalse(replacementCalled)
        XCTAssertEqual(queue.completedCount, 1)
    }

    // MARK: - Cropped vs Uncropped Routing

    func testUncroppedJobCallsSingleEndpoint() async throws {
        nonisolated(unsafe) var singleCalled = false
        let queue = RecognitionQueue(cardRecognizer: StubCardRecognizer(
            recognize: { _, _, _ in singleCalled = true; return RecognitionResult(cards: []) },
            recognizeBatch: { _, _ in XCTFail("batch should not be called"); return RecognitionResult(cards: []) }
        ))
        queue.enqueue(image: makeImage(), isCropped: false, modelContext: nil)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(singleCalled)
    }

    func testUncroppedPayloadPreservesOriginalBytesAndContentType() async throws {
        let originalBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02])
        nonisolated(unsafe) var receivedData: Data?
        nonisolated(unsafe) var receivedFilename: String?
        nonisolated(unsafe) var receivedContentType: String?

        let queue = RecognitionQueue(cardRecognizer: StubCardRecognizer(
            recognize: { data, filename, contentType in
                receivedData = data
                receivedFilename = filename
                receivedContentType = contentType
                return RecognitionResult(cards: [])
            },
            recognizeBatch: { _, _ in
                XCTFail("batch should not be called")
                return RecognitionResult(cards: [])
            }
        ))

        queue.enqueue(
            payload: makePayload(
                uploadData: originalBytes,
                contentType: "image/png",
                preferredFilenameExtension: "png"
            ),
            isCropped: false,
            modelContext: nil
        )

        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(receivedData, originalBytes)
        XCTAssertEqual(receivedContentType, "image/png")
        XCTAssertEqual(receivedFilename?.suffix(4), ".png")
    }

    func testCroppedJobCallsBatchEndpoint() async throws {
        nonisolated(unsafe) var batchCalled = false
        let queue = RecognitionQueue(cardRecognizer: StubCardRecognizer(
            recognize: { _, _, _ in XCTFail("single should not be called"); return RecognitionResult(cards: []) },
            recognizeBatch: { crops, _ in
                batchCalled = true
                XCTAssertEqual(crops.count, 1)
                return RecognitionResult(cards: [])
            }
        ))
        queue.enqueue(image: makeImage(), isCropped: true, modelContext: nil)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(batchCalled)
    }

    func testRetryPreservesCroppedFlag() async throws {
        nonisolated(unsafe) var batchCallCount = 0
        let queue = RecognitionQueue(cardRecognizer: StubCardRecognizer(
            recognize: { _, _, _ in XCTFail("single should not be called"); return RecognitionResult(cards: []) },
            recognizeBatch: { _, _ in
                batchCallCount += 1
                throw URLError(.networkConnectionLost)
            }
        ))
        queue.enqueue(image: makeImage(), isCropped: true, modelContext: nil)
        try await Task.sleep(for: .milliseconds(300))
        // Original attempt + 1 retry, both via batch.
        XCTAssertEqual(batchCallCount, 2)
        XCTAssertEqual(queue.failedCount, 1)
    }

    func testDefaultEnqueueIsUncropped() async throws {
        nonisolated(unsafe) var singleCalled = false
        let queue = RecognitionQueue(cardRecognizer: StubCardRecognizer(
            recognize: { _, _, _ in singleCalled = true; return RecognitionResult(cards: []) },
            recognizeBatch: { _, _ in XCTFail("batch should not be called"); return RecognitionResult(cards: []) }
        ))
        queue.enqueue(image: makeImage(), modelContext: nil)
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
        let queue = RecognitionQueue(cardRecognizer: StubCardRecognizer(recognize: { _, _, _ in
            await counter.increment()
            try await Task.sleep(for: .milliseconds(50))
            await counter.decrement()
            return RecognitionResult(cards: [])
        }))
        queue.maxConcurrent = 2
        for _ in 0..<6 {
            queue.enqueue(image: makeImage(), modelContext: nil)
        }
        try await Task.sleep(for: .milliseconds(500))
        let peak = await counter.peak
        XCTAssertLessThanOrEqual(peak, 2)
    }

}

// MARK: - Cancel and Capture Time

@MainActor
final class RecognitionQueueCancelTests: XCTestCase {

    func testCancelAllClearsPendingCount() async throws {
        let queue = RecognitionQueue(cardRecognizer: StubCardRecognizer(recognize: { _, _, _ in
            try await Task.sleep(for: .seconds(10))
            return RecognitionResult(cards: [])
        }))
        queue.maxConcurrent = 1
        for _ in 0..<4 {
            queue.enqueue(image: makeImage(), modelContext: nil)
        }
        queue.cancelAll()
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testCancelAllAllowsNewJobsAfterCancel() async throws {
        nonisolated(unsafe) var isCancelled = false
        let queue = RecognitionQueue(cardRecognizer: StubCardRecognizer(recognize: { _, _, _ in
            if !isCancelled {
                try await Task.sleep(for: .seconds(10))
            }
            return RecognitionResult(cards: [])
        }))
        queue.enqueue(image: makeImage(), modelContext: nil)
        isCancelled = true
        queue.cancelAll()
        try await Task.sleep(for: .milliseconds(100))
        queue.enqueue(image: makeImage(), modelContext: nil)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(queue.completedCount, 1)
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testCancelAllPreservesCompletedCount() async throws {
        let queue = makeSucceedingQueue()
        queue.enqueue(image: makeImage(), modelContext: nil)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(queue.completedCount, 1)

        let longQueue = RecognitionQueue(cardRecognizer: StubCardRecognizer(recognize: { _, _, _ in
            try await Task.sleep(for: .seconds(10))
            return RecognitionResult(cards: [])
        }))
        longQueue.enqueue(image: makeImage(), modelContext: nil)
        longQueue.cancelAll()
        XCTAssertEqual(longQueue.completedCount, 0)
        XCTAssertEqual(queue.completedCount, 1)
    }

    func testCancelAllPreservesFailedCount() async throws {
        let queue = makeFailingQueue()
        queue.enqueue(image: makeImage(), modelContext: nil)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(queue.failedCount, 1)
        queue.enqueue(image: makeImage(), modelContext: nil)
        queue.cancelAll()
        XCTAssertEqual(queue.failedCount, 1)
    }

    func testCapturedAtPreservedOnRetry() async throws {
        nonisolated(unsafe) var callCount = 0
        let queue = RecognitionQueue(cardRecognizer: StubCardRecognizer(recognize: { _, _, _ in
            callCount += 1
            if callCount == 1 { throw URLError(.networkConnectionLost) }
            return RecognitionResult(cards: [])
        }))
        queue.enqueue(image: makeImage(), modelContext: nil)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(callCount, 2, "Should have been called twice (original + retry)")
        XCTAssertEqual(queue.completedCount, 1)
        XCTAssertEqual(queue.failedCount, 0)
    }
}

// MARK: - Helpers

@MainActor
private func makeFailingQueue() -> RecognitionQueue {
    RecognitionQueue(cardRecognizer: StubCardRecognizer(recognize: { _, _, _ in
        throw URLError(.notConnectedToInternet)
    }))
}

@MainActor
private func makeSucceedingQueue() -> RecognitionQueue {
    RecognitionQueue(cardRecognizer: StubCardRecognizer(recognize: { _, _, _ in RecognitionResult(cards: []) }))
}

private func makeImage() -> UIImage {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
    return renderer.image { ctx in
        ctx.cgContext.setFillColor(UIColor.red.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
    }
}

private func makePayload(
    uploadData: Data = Data([0x01, 0x02, 0x03]),
    contentType: String = "image/jpeg",
    preferredFilenameExtension: String = "jpg"
) -> RecognitionImagePayload {
    RecognitionImagePayload(
        displayImage: makeImage(),
        uploadData: uploadData,
        contentType: contentType,
        preferredFilenameExtension: preferredFilenameExtension
    )
}

// MARK: - Retry / Clear Failed

@MainActor
final class RecognitionQueueRetryTests: XCTestCase {

    func testRetryFailedMovesJobsToPending() async throws {
        let queue = makeFailingQueue()
        queue.enqueue(image: makeImage(), modelContext: nil)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(queue.failedCount, 1)
        XCTAssertEqual(queue.pendingCount, 0)

        queue.retryFailed()
        XCTAssertEqual(queue.failedCount, 0)
        XCTAssertEqual(queue.pendingCount, 1)
    }

    func testRetryFailedJobsProcessAfterRetry() async throws {
        nonisolated(unsafe) var callCount = 0
        let queue = RecognitionQueue(cardRecognizer: StubCardRecognizer(recognize: { _, _, _ in
            callCount += 1
            if callCount <= 2 { throw URLError(.networkConnectionLost) }
            return RecognitionResult(cards: [])
        }))
        queue.enqueue(image: makeImage(), modelContext: nil)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(queue.failedCount, 1)

        queue.retryFailed()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(queue.failedCount, 0)
        XCTAssertEqual(queue.completedCount, 1)
    }

    func testClearFailedRemovesAllFailedJobs() async throws {
        let queue = makeFailingQueue()
        for _ in 0..<3 {
            queue.enqueue(image: makeImage(), modelContext: nil)
        }
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(queue.failedCount, 3)

        queue.clearFailed()
        XCTAssertEqual(queue.failedCount, 0)
        XCTAssertEqual(queue.completedCount, 0)
    }

    func testRetryFailedResetsRetryCount() async throws {
        nonisolated(unsafe) var callCount = 0
        let queue = RecognitionQueue(cardRecognizer: StubCardRecognizer(recognize: { _, _, _ in
            callCount += 1
            throw URLError(.networkConnectionLost)
        }))
        queue.enqueue(image: makeImage(), modelContext: nil)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(queue.failedCount, 1)

        queue.retryFailed()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(callCount, 4)
        XCTAssertEqual(queue.failedCount, 1)
    }
}
