import SwiftData
import XCTest
@testable import MTGScannerKit

/// Covers the Results tab badge: what it counts and how it renders.
@MainActor
final class ScanSessionCounterTests: XCTestCase {

    // MARK: - Badge formatting

    func testBadgeHidesAtZeroAndBelow() {
        XCTAssertNil(ScanSessionCounter.badgeText(for: 0))
        XCTAssertNil(ScanSessionCounter.badgeText(for: -3))
    }

    func testBadgeShowsBareDigits() {
        XCTAssertEqual(ScanSessionCounter.badgeText(for: 1), "1")
        XCTAssertEqual(ScanSessionCounter.badgeText(for: 4), "4")
        XCTAssertEqual(ScanSessionCounter.badgeText(for: 999), "999")
    }

    func testBadgeClampsAbove999() {
        XCTAssertEqual(ScanSessionCounter.badgeText(for: 1_000), "999+")
        XCTAssertEqual(ScanSessionCounter.badgeText(for: 40_000), "999+")
    }

    // MARK: - Plumbing: what reaches Results is what the badge counts

    /// A four-card sheet is one upload and four cards, so the badge must read 4.
    /// Removing the `onScanBatch` call in `RecognitionQueue.persist` fails this.
    func testBatchReportingFiresOnceWithEveryCardInThatBatch() async throws {
        let context = try makeContext()
        nonisolated(unsafe) var reported: [[String]] = []
        let queue = RecognitionQueue(recognize: { _, _, _, _ in
            RecognitionResult(cards: (1...4).map { RecognizedCard(title: "Card \($0)") })
        })
        queue.onScanBatch = { cards in reported.append(cards.map { $0.title ?? "" }) }

        queue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: context)
        await waitUntil("the four-card upload to finish") { queue.completedCount == 1 }

        XCTAssertEqual(reported, [["Card 1", "Card 2", "Card 3", "Card 4"]])
        let items = try context.fetch(FetchDescriptor<CollectionItem>())
        XCTAssertEqual(items.count, 4, "reported count must match what actually reached Results")
    }

    /// Retries must not inflate the tally: one card that fails then succeeds is still 1.
    func testRetriedBatchReportsOnlyOnce() async throws {
        let context = try makeContext()
        nonisolated(unsafe) var attempt = 0
        nonisolated(unsafe) var reportedCounts: [Int] = []
        let queue = RecognitionQueue(recognize: { _, _, _, _ in
            attempt += 1
            if attempt == 1 { throw URLError(.networkConnectionLost) }
            return RecognitionResult(cards: [RecognizedCard(title: "Lightning Bolt")])
        })
        queue.onScanBatch = { cards in reportedCounts.append(cards.count) }

        queue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: context)
        await waitUntil("the retried upload to finish") { queue.completedCount == 1 }

        XCTAssertEqual(attempt, 2, "expected the upload to be retried once")
        XCTAssertEqual(reportedCounts, [1], "a retried upload is still one report of one card")
    }

    /// A sheet where the API identifies nothing must not light up the badge.
    func testBatchWithNoIdentifiedCardsIsNotReported() async throws {
        let context = try makeContext()
        nonisolated(unsafe) var didReport = false
        let queue = RecognitionQueue(recognize: { _, _, _, _ in RecognitionResult(cards: []) })
        queue.onScanBatch = { _ in didReport = true }

        queue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: context)
        await waitUntil("the no-card upload to finish") { queue.completedCount == 1 }

        XCTAssertFalse(didReport, "an upload that completed without a report added nothing")
    }

    // MARK: - AppModel tally

    /// A real AppModel connected to a real queue, like ScanView connects on appear.
    /// Manual Scan and Auto Scan both enqueue into that queue, so both modes are covered.
    /// The first upload returns 4 cards and the second 2, so the tally goes 4 then 6.
    func testQueueBatchesAddToAppModelCount() async throws {
        let context = try makeContext()
        let appModel = AppModel()
        appModel.modelContext = context
        nonisolated(unsafe) var call = 0
        let queue = RecognitionQueue(recognize: { _, _, _, _ in
            call += 1
            let titles = call == 1
                ? (1...4).map { "Card \($0)" }
                : ["Lightning Bolt", "Counterspell"]
            return RecognitionResult(cards: titles.map { RecognizedCard(title: $0) })
        })
        appModel.connectScanCounter(to: queue)

        queue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: context)
        await waitUntil("the four-card upload to be counted") { appModel.scanSessionCount == 4 }
        XCTAssertEqual(appModel.scanSessionCount, 4, "an upload that returns 4 cards adds 4")

        queue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: context)
        await waitUntil("the two-card upload to be counted") { appModel.scanSessionCount == 6 }
        XCTAssertEqual(appModel.scanSessionCount, 6, "the second upload adds its own 2 cards")
    }

    /// Wiring stays once per queue: re-entering the Scan tab must not double count.
    func testConnectingTwiceDoesNotDoubleCount() async throws {
        let context = try makeContext()
        let appModel = AppModel()
        appModel.modelContext = context
        let queue = RecognitionQueue(recognize: { _, _, _, _ in
            RecognitionResult(cards: (1...4).map { RecognizedCard(title: "Card \($0)") })
        })
        appModel.connectScanCounter(to: queue)
        appModel.connectScanCounter(to: queue)

        queue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: context)
        await waitUntil("the four-card upload to be counted") { appModel.scanSessionCount == 4 }

        XCTAssertEqual(appModel.scanSessionCount, 4, "one queue carries one subscription")
    }

    func testClearScanSessionCountResetsToZero() {
        let appModel = AppModel()
        appModel.scanSessionCount = 5
        appModel.clearScanSessionCount()
        XCTAssertEqual(appModel.scanSessionCount, 0, "opening Results empties the tally")
    }

    /// Only opening Results clears the tally: stopping Auto Scan must not touch it.
    func testStoppingAutoScanKeepsCount() async throws {
        let context = try makeContext()
        let appModel = AppModel()
        appModel.modelContext = context
        let queue = RecognitionQueue(recognize: { _, _, _, _ in
            RecognitionResult(cards: (1...3).map { RecognizedCard(title: "Card \($0)") })
        })
        appModel.connectScanCounter(to: queue)
        let vm = AutoScanViewModel(detectorProvider: { nil }, recognitionQueue: queue)

        queue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: context)
        await waitUntil("the three-card upload to be counted") { appModel.scanSessionCount == 3 }

        vm.stop()
        XCTAssertEqual(appModel.scanSessionCount, 3, "stopping Auto Scan leaves the tally alone")
    }

    // MARK: - Fixtures

    /// Polls `condition` on the main actor until it turns true, or fails the test.
    /// Yields between checks so the queue's MainActor tasks can run, instead of
    /// betting on a fixed sleep that either flakes or wastes CI seconds.
    private func waitUntil(_ what: String, _ condition: @MainActor () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for \(what)")
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: CollectionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }
    }
}
