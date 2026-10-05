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
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(reported, [["Card 1", "Card 2", "Card 3", "Card 4"]])
        let items = try context.fetch(FetchDescriptor<CollectionItem>())
        XCTAssertEqual(items.count, 4, "reported count must match what actually reached Results")
    }

    /// Retries must not inflate the tally: one card that fails then succeeds is still 1.
    func testRetriedBatchReportsOnlyOnce() async throws {
        let context = try makeContext()
        nonisolated(unsafe) var attempt = 0
        nonisolated(unsafe) var reportedCount: Int?
        let queue = RecognitionQueue(recognize: { _, _, _, _ in
            attempt += 1
            if attempt == 1 { throw URLError(.networkConnectionLost) }
            return RecognitionResult(cards: [RecognizedCard(title: "Lightning Bolt")])
        })
        queue.onScanBatch = { cards in reportedCount = cards.count }

        queue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: context)
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(attempt, 2, "expected the upload to be retried once")
        XCTAssertEqual(reportedCount, 1, "a retried upload is still one card, not two")
    }

    /// A sheet where the API identifies nothing must not light up the badge.
    func testBatchWithNoIdentifiedCardsIsNotReported() async throws {
        let context = try makeContext()
        nonisolated(unsafe) var didReport = false
        let queue = RecognitionQueue(recognize: { _, _, _, _ in RecognitionResult(cards: []) })
        queue.onScanBatch = { _ in didReport = true }

        queue.enqueue(image: makeImage(), apiBaseURL: "http://localhost", modelContext: context)
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertFalse(didReport)
    }

    // MARK: - Fixtures

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
