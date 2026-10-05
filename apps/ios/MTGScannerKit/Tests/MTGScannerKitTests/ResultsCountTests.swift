import SwiftData
import UIKit
import XCTest
@testable import MTGScannerKit

final class ResultsCountTests: XCTestCase {
    private let keys = ["results_count_mode", "scan_session_count"]
    private var savedDefaults: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        for key in keys {
            savedDefaults[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in keys { UserDefaults.standard.set(savedDefaults[key], forKey: key) }
        savedDefaults.removeAll()
        super.tearDown()
    }

    @MainActor
    func testPreferencesAndCountPersistUntilExplicitReset() {
        let model = AppModel()
        XCTAssertEqual(model.resultsCountMode, .session)
        XCTAssertEqual(model.scanSessionCount, 0)
        model.recordScannedCard()
        model.resultsCountMode = .off
        model.recordScannedCard()
        let relaunched = AppModel()
        XCTAssertEqual(relaunched.resultsCountMode, .off)
        XCTAssertEqual(relaunched.scanSessionCount, 2)
        relaunched.resultsCountMode = .allResults
        XCTAssertEqual(relaunched.scanSessionCount, 2)
        relaunched.resetScanCount()
        XCTAssertEqual(AppModel().scanSessionCount, 0)
        relaunched.recordScannedCard()
        XCTAssertEqual(relaunched.scanSessionCount, 1)
    }

    @MainActor
    func testInvalidStoredPreferencesUseDefaults() {
        UserDefaults.standard.set("unknown", forKey: keys[0])
        UserDefaults.standard.set(-4, forKey: keys[1])
        let model = AppModel()
        XCTAssertEqual(model.resultsCountMode, .session)
        XCTAssertEqual(model.scanSessionCount, 0)
    }

    @MainActor
    func testRecognitionCountsCardsAndNeverReusesPreviousResponseOnFailure() throws {
        let container = try makeContainer()
        let model = AppModel()
        model.modelContext = container.mainContext
        let card = try XCTUnwrap(RecognitionResult.sample.cards.first)
        model.finishRecognition(RecognitionResult(cards: [card, card]))
        XCTAssertEqual(model.scanSessionCount, 2)
        model.shouldShowResults = false
        model.finishRecognition(nil)
        XCTAssertFalse(model.shouldShowResults)
        XCTAssertEqual(model.scanSessionCount, 2)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<CollectionItem>()).count, 2)
        model.finishRecognition(RecognitionResult(cards: []))
        XCTAssertEqual(model.scanSessionCount, 2)
        model.resetScanCount()
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<CollectionItem>()).count, 2)
    }

    @MainActor
    func testRecognitionWithoutPersistenceDoesNotCount() {
        let model = AppModel()
        model.finishRecognition(.sample)
        XCTAssertEqual(model.scanSessionCount, 0)
    }

    @MainActor
    func testCancelledRecognitionDoesNotPersistOrCount() async throws {
        let container = try makeContainer()
        let model = AppModel()
        model.modelContext = container.mainContext
        let task = Task { @MainActor in model.finishRecognition(.sample) }
        task.cancel()
        await task.value
        XCTAssertEqual(model.scanSessionCount, 0)
        XCTAssertFalse(model.shouldShowResults)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<CollectionItem>()).isEmpty)
    }

    func testBadgeModesAndOverflowKeepExactAccessibleCount() {
        XCTAssertNil(ResultsCountMode.session.badge(sessionCount: 0, resultQuantity: 8))
        XCTAssertNil(ResultsCountMode.off.badge(sessionCount: 5, resultQuantity: 8))
        XCTAssertEqual(ResultsCountMode.session.badge(sessionCount: 5, resultQuantity: 8), "5")
        XCTAssertEqual(ResultsCountMode.allResults.badge(sessionCount: 5, resultQuantity: 8), "8")
        XCTAssertEqual(ResultsCountMode.session.badge(sessionCount: 999, resultQuantity: 0), "999")
        XCTAssertEqual(ResultsCountMode.session.badge(sessionCount: 1000, resultQuantity: 0), "999+")
        XCTAssertEqual(ResultsCountMode.session.accessibilityValue(sessionCount: 1000, resultQuantity: 0),
                       "1000 cards scanned this session")
    }

    @MainActor
    func testInboxCountUsesQuantitiesAndIgnoresLibraryItems() throws {
        let container = try makeContainer()
        let card = try XCTUnwrap(RecognitionResult.sample.cards.first)
        let first = CollectionItem(from: card, correction: nil)
        let second = CollectionItem(from: card, correction: nil)
        first.quantity = 3
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        let predicate = #Predicate<CollectionItem> { $0.collection == nil && $0.deck == nil }
        let descriptor = FetchDescriptor(predicate: predicate)
        XCTAssertEqual(try container.mainContext.fetch(descriptor).totalQuantity, 4)
        let collection = CardCollection(name: "Binder")
        container.mainContext.insert(collection)
        first.collection = collection
        XCTAssertEqual(try container.mainContext.fetch(descriptor).totalQuantity, 1)
        container.mainContext.delete(second)
        XCTAssertEqual(try container.mainContext.fetch(descriptor).totalQuantity, 0)
    }

    @MainActor
    func testQueueCompletionAfterResetCountsCardsAndPreservesToasts() async throws {
        let container = try makeContainer()
        let model = AppModel()
        model.recordScannedCard()
        let queue = RecognitionQueue(recognize: { _, _, _, _ in
            try await Task.sleep(for: .milliseconds(80))
            return .sample
        })
        let viewModel = AutoScanViewModel(recognitionQueue: queue)
        viewModel.onCardIdentified = { [weak model] _ in model?.recordScannedCard() }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30)).image { context in
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        }
        queue.enqueue(image: image, apiBaseURL: "http://fixture.invalid", modelContext: container.mainContext)
        model.resetScanCount()
        for _ in 0..<100 where queue.pendingCount > 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(queue.completedCount, 1)
        XCTAssertEqual(model.scanSessionCount, 1)
        XCTAssertEqual(viewModel.identifiedCardsViewModel.recentCards.count, 1)
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: CollectionItem.self, CardCollection.self, Deck.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
}
