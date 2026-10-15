import SwiftData
import XCTest
@testable import MTGScannerKit

@MainActor
final class CardTransferViewModelTests: XCTestCase {
    func testInitialStateRequiresDestinationAndCountsFullStacks() {
        let model = CardTransferViewModel(items: [item(4), item(2)], operation: .move)
        XCTAssertEqual(model.operation, .move)
        XCTAssertNil(model.destination)
        XCTAssertEqual(model.rows.map(\.quantity), [4, 2])
        XCTAssertEqual(model.summary, "6 cards across 2 selected rows")
        XCTAssertFalse(model.canSubmit)
        XCTAssertFalse(CardTransferViewModel(items: [], operation: .copy).canSubmit)
    }

    func testDestinationSelectionAndNavigationDoNotPersistOrResetQuantities() throws {
        let context = try context()
        let source = item(4)
        context.insert(source)
        try context.save()
        let model = CardTransferViewModel(items: [source], operation: .copy)
        model.setQuantity(2, for: source.id)
        model.showDestinations()
        let first = Deck(name: "Draft deck")
        model.select(.deck(first))
        XCTAssertTrue(model.path.isEmpty)
        XCTAssertTrue(model.canSubmit)
        model.showDestinations()
        model.path = [] // Native back navigation.
        XCTAssertEqual(model.destination?.name, "Draft deck")
        model.reviewQuantities(in: context)
        XCTAssertEqual(model.path, [.quantities])
        model.path = []
        XCTAssertEqual(model.rows.first?.quantity, 2)
        XCTAssertEqual(model.summary, "2 cards across 1 selected row")
        model.select(.collection(CardCollection(name: "Draft collection")))
        XCTAssertEqual(model.destination?.name, "Draft collection")
        XCTAssertEqual(source.quantity, 4)
        XCTAssertNil(source.deck)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Deck>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CardCollection>()).isEmpty)
    }

    func testQuantityChangesClampToAvailableBounds() {
        let source = item(4)
        let model = CardTransferViewModel(items: [source], operation: .copy)
        model.setQuantity(0, for: source.id)
        XCTAssertEqual(model.rows.first?.quantity, 1)
        model.setQuantity(100, for: source.id)
        XCTAssertEqual(model.rows.first?.quantity, 4)
    }

    func testPickerFilterExcludesEverySourceList() {
        let collection = CardCollection(name: "Source")
        let deck = Deck(name: "Source deck")
        let first = item(2)
        let second = item(1)
        first.collection = collection
        second.deck = deck
        let model = CardTransferViewModel(items: [first, second], operation: .move)
        XCTAssertFalse(model.destinationFilter.includes(.collection(collection)))
        XCTAssertFalse(model.destinationFilter.includes(.deck(deck)))
        XCTAssertTrue(model.destinationFilter.includes(.deck(Deck(name: "Other"))))
        model.select(.deck(deck))
        XCTAssertNil(model.destination)
    }

    func testSubmitCopiesAndMovesExactQuantitiesAndCompletesOnce() throws {
        for operation in CardTransferOperation.allCases {
            let context = try context()
            let source = item(4)
            context.insert(source)
            try context.save()
            let target = Deck(name: "New deck")
            let model = CardTransferViewModel(items: [source], operation: operation)
            model.setQuantity(2, for: source.id)
            model.select(.deck(target))
            var results: [CardTransferResult] = []
            model.submit(in: context) { results.append($0) }
            model.submit(in: context) { results.append($0) }
            XCTAssertEqual(source.quantity, operation == .copy ? 4 : 2)
            XCTAssertEqual(target.items.first?.quantity, 2)
            XCTAssertEqual(try context.fetch(FetchDescriptor<Deck>()).map(\.name), ["New deck"])
            XCTAssertEqual(results.count, 1)
            XCTAssertEqual(results.first?.operation, operation)
            XCTAssertTrue(model.isDismissed)
            XCTAssertNil(model.errorMessage)
        }
    }

    func testCancelPreservesSourceAndCreatesNoDraftDestinations() throws {
        for destinationKind in 0...1 {
            let context = try context()
            let source = item(4)
            context.insert(source)
            try context.save()
            let model = CardTransferViewModel(items: [source], operation: .move)
            model.select(destinationKind == 0 ? .deck(Deck(name: "Draft"))
                         : .collection(CardCollection(name: "Draft")))
            model.cancel()
            model.submit(in: context) { _ in XCTFail("Cancelled transfer completed") }
            XCTAssertEqual(source.quantity, 4)
            XCTAssertNil(source.deck)
            XCTAssertNil(source.collection)
            XCTAssertTrue(try context.fetch(FetchDescriptor<Deck>()).isEmpty)
            XCTAssertTrue(try context.fetch(FetchDescriptor<CardCollection>()).isEmpty)
        }
    }

    func testChangedAndDeletedSourcesKeepErrorUntilReviewClampsAndRemovesRows() throws {
        let context = try context()
        let changed = item(4)
        let deleted = item(2)
        context.insert(changed)
        context.insert(deleted)
        try context.save()
        let model = CardTransferViewModel(items: [changed, deleted], operation: .move)
        model.select(.deck(Deck(name: "Draft")))
        changed.quantity = 2
        context.delete(deleted)
        try context.save()
        model.submit(in: context) { _ in XCTFail("Stale transfer completed") }
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isDismissed)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Deck>()).isEmpty)
        model.reviewQuantities(in: context)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.path, [.quantities])
        XCTAssertEqual(model.rows.map(\.id), [changed.id])
        XCTAssertEqual(model.rows.first?.quantity, 2)
        XCTAssertEqual(model.rows.first?.availableQuantity, 2)
        model.submit(in: context) { _ in }
        XCTAssertTrue(model.isDismissed)
    }

    func testReviewClosesWithoutSuccessWhenAllSourcesWereDeleted() throws {
        let context = try context()
        let source = item(4)
        context.insert(source)
        try context.save()
        let model = CardTransferViewModel(items: [source], operation: .copy)
        model.select(.collection(CardCollection(name: "Draft")))
        context.delete(source)
        try context.save()
        model.submit(in: context) { _ in XCTFail("Deleted source completed") }
        XCTAssertNotNil(model.errorMessage)
        model.reviewQuantities(in: context)
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertTrue(model.isDismissed)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CardCollection>()).isEmpty)
    }

    func testMissingDestinationCannotSubmit() throws {
        let context = try context()
        let source = item(4)
        context.insert(source)
        let model = CardTransferViewModel(items: [source], operation: .copy)
        model.submit(in: context) { _ in XCTFail("Missing destination completed") }
        XCTAssertFalse(model.isDismissed)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectionItem>()).count, 1)
    }

    func testSaveFailureDoesNotCompleteOrInsertDraftDestination() throws {
        let context = try context()
        let source = item(4)
        context.insert(source)
        try context.save()
        let model = CardTransferViewModel(items: [source], operation: .move)
        let target = CardCollection(name: "Draft")
        model.select(.collection(target))
        model.submit(in: context, save: { throw CardTransferError.sourceChanged }, onComplete: { _ in
            XCTFail("Failed save completed")
        })
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isDismissed)
        XCTAssertNil(target.modelContext)
        XCTAssertEqual(source.quantity, 4)
        XCTAssertNil(source.collection)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CardCollection>()).isEmpty)
        model.reviewQuantities(in: context)
        model.submit(in: context) { _ in }
        XCTAssertTrue(model.isDismissed)
        let saved = try XCTUnwrap(context.fetch(FetchDescriptor<CardCollection>()).first)
        XCTAssertEqual(saved.name, "Draft")
        XCTAssertEqual(saved.items.first?.quantity, 4)
    }

    func testSuccessfulSubmissionPersistsDraftCollectionWithCards() throws {
        let context = try context()
        let source = item(4)
        context.insert(source)
        try context.save()
        let model = CardTransferViewModel(items: [source], operation: .copy)
        model.select(.collection(CardCollection(name: "New collection")))
        model.submit(in: context) { _ in }
        let saved = try XCTUnwrap(context.fetch(FetchDescriptor<CardCollection>()).first)
        XCTAssertEqual(saved.name, "New collection")
        XCTAssertEqual(saved.items.first?.quantity, 4)
        XCTAssertTrue(model.isDismissed)
    }

    private func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: CollectionItem.self, CardCollection.self, Deck.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func item(_ quantity: Int) -> CollectionItem {
        CollectionItem(title: "Sol Ring", edition: "Commander", collectorNumber: "1", quantity: quantity)
    }
}
