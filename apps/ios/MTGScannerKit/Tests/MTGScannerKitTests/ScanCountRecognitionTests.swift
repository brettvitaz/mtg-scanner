import SwiftData
import UIKit
import XCTest
@testable import MTGScannerKit

@MainActor
final class ScanCountRecognitionTests: XCTestCase {
    func testManualAndAutoRunsCountEachInsertedCardAndPreserveToasts() async throws {
        let app = AppModel()
        let context = try makeScanCountContext()
        let queue = successfulQueue()
        let vm = makeViewModel(app: app, queue: queue, context: context)
        await vm.enqueueCapturedImage(payload(), cropEnabled: false)
        await waitForQueue(queue)
        XCTAssertEqual(app.newlyScannedCardCount, 2)
        vm.start()
        await vm.processAutoCapturedPayload(payload())
        await waitForQueue(queue)
        vm.stop()
        vm.start()
        await vm.enqueueCapturedImage(payload(), cropEnabled: false)
        await waitForQueue(queue)
        XCTAssertEqual(app.newlyScannedCardCount, 6)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectionItem>()), 6)
        XCTAssertEqual(vm.identifiedCardsViewModel.recentCards.count, 2)
        vm.stop()
    }

    func testRetryCountsSuccessOnce() async throws {
        let attempts = ScanCountAttempts()
        let app = AppModel()
        let context = try makeScanCountContext()
        let queue = RecognitionQueue(recognize: { _, _, _, _ in
            if await attempts.next() == 1 { throw URLError(.notConnectedToInternet) }
            return Self.cards()
        })
        let vm = makeViewModel(app: app, queue: queue, context: context)
        await vm.enqueueCapturedImage(payload(), cropEnabled: false)
        await waitForQueue(queue)
        XCTAssertEqual(app.newlyScannedCardCount, 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectionItem>()), 2)
    }

    func testFailedEmptyAndUnpersistedResponsesAddNothing() async throws {
        let app = AppModel()
        let context = try makeScanCountContext()
        let queues = [
            RecognitionQueue(recognize: { _, _, _, _ in throw URLError(.notConnectedToInternet) }),
            RecognitionQueue(recognize: { _, _, _, _ in RecognitionResult(cards: []) }),
            successfulQueue()
        ]
        for (index, queue) in queues.enumerated() {
            let vm = makeViewModel(app: app, queue: queue, context: index == 2 ? nil : context)
            await vm.enqueueCapturedImage(payload(), cropEnabled: false)
            await waitForQueue(queue)
            XCTAssertEqual(app.newlyScannedCardCount, 0)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectionItem>()), 0)
    }

    func testPendingAndCancelledRecognitionsAddNothing() async throws {
        let gate = ScanCountRecognitionGate()
        let app = AppModel()
        let context = try makeScanCountContext()
        let attempts = ScanCountAttempts()
        let queue = RecognitionQueue(recognize: { _, _, _, _ in
            if await attempts.next() == 1 { return await gate.result() }
            return Self.cards()
        })
        queue.maxConcurrent = 1
        defer { queue.cancelAll(); Task { await gate.finish(RecognitionResult(cards: [])) } }
        let vm = makeViewModel(app: app, queue: queue, context: context)
        await vm.enqueueCapturedImage(payload(), cropEnabled: false)
        try await gate.waitUntilStarted()
        XCTAssertEqual(app.newlyScannedCardCount, 0)
        queue.cancelAll()
        await gate.finish(Self.cards())
        for _ in 0..<20 { await Task.yield() }
        // With one worker, this job can finish only after the cancelled worker has exited.
        await vm.enqueueCapturedImage(payload(), cropEnabled: false)
        await waitForQueue(queue)
        XCTAssertEqual(queue.completedCount, 1)
        XCTAssertEqual(app.newlyScannedCardCount, 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectionItem>()), 2)
        XCTAssertEqual(vm.identifiedCardsViewModel.recentCards.count, 2)
    }

    func testLateCompletionWhileResultsIsSelectedIsSeen() async throws {
        try await assertLateCompletion(resultsStillSelected: true, expectedCount: 0)
    }

    func testLateCompletionAfterLeavingResultsStartsNewCount() async throws {
        try await assertLateCompletion(resultsStillSelected: false, expectedCount: 2)
    }

    private func assertLateCompletion(resultsStillSelected: Bool, expectedCount: Int) async throws {
        let gate = ScanCountRecognitionGate()
        let app = AppModel()
        let context = try makeScanCountContext()
        let queue = RecognitionQueue(recognize: { _, _, _, _ in await gate.result() })
        defer { queue.cancelAll(); Task { await gate.finish(RecognitionResult(cards: [])) } }
        let vm = makeViewModel(app: app, queue: queue, context: context)
        await vm.enqueueCapturedImage(payload(), cropEnabled: false)
        try await gate.waitUntilStarted()
        app.recordScannedCard()
        app.selectTab(1)
        vm.stop()
        if !resultsStillSelected { app.selectTab(3) }
        await gate.finish(Self.cards())
        await waitForQueue(queue)
        XCTAssertEqual(app.newlyScannedCardCount, expectedCount)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectionItem>()), 2)
    }

    private func successfulQueue() -> RecognitionQueue {
        RecognitionQueue(
            recognize: { _, _, _, _ in Self.cards() },
            recognizeBatch: { _, _, _ in Self.cards() }
        )
    }

    nonisolated private static func cards() -> RecognitionResult {
        RecognitionResult(cards: [
            RecognizedCard(title: "Island", edition: "Test"),
            RecognizedCard(title: "Island", edition: "Test")
        ])
    }

    private func makeViewModel(app: AppModel, queue: RecognitionQueue, context: ModelContext?) -> AutoScanViewModel {
        let vm = AutoScanViewModel(detectorProvider: { nil }, recognitionQueue: queue,
                                   cropImage: { _, _ in CardCropResult(crops: [], detectedCount: 0) })
        vm.appModel = app
        vm.modelContext = context
        return vm
    }

    private func payload() -> RecognitionImagePayload {
        RecognitionImagePayload(displayImage: UIImage(), uploadData: Data([1]),
                                contentType: "image/jpeg", preferredFilenameExtension: "jpg")
    }

    private func waitForQueue(_ queue: RecognitionQueue) async {
        for _ in 0..<200 where queue.pendingCount > 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(queue.pendingCount, 0, "Recognition did not settle")
    }
}

private actor ScanCountAttempts {
    private var count = 0
    func next() -> Int { count += 1; return count }
}

private actor ScanCountRecognitionGate {
    private var continuation: CheckedContinuation<RecognitionResult, Never>?

    func result() async -> RecognitionResult {
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async throws {
        for _ in 0..<200 {
            if continuation != nil { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw URLError(.timedOut)
    }

    func finish(_ result: RecognitionResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
