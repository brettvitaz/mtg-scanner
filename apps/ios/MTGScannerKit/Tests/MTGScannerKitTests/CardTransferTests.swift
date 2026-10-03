import SwiftData
import XCTest
@testable import MTGScannerKit

@MainActor
final class CardTransferTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: CollectionItem.self, CardCollection.self, Deck.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeItem(quantity: Int = 4, foil: Bool = false) -> CollectionItem {
        CollectionItem(title: "Sol Ring", edition: "Commander", setCode: "C21",
                       collectorNumber: "263", foil: foil, scryfallId: "sol-ring-c21",
                       priceRetail: "$2.00", quantity: quantity)
    }

    func testCopyAndMoveAcrossAllSourceAndDestinationTypes() throws {
        for operation in CardTransferOperation.allCases {
            for sourceKind in 0...2 {
                for targetKind in 0...1 {
                    try checkTransfer(operation: operation, sourceKind: sourceKind, targetKind: targetKind)
                }
            }
        }
    }

    private func checkTransfer(
        operation: CardTransferOperation, sourceKind: Int, targetKind: Int
    ) throws {
        let context = try makeContext()
        let sourceCollection = CardCollection(name: "Source collection")
        let sourceDeck = Deck(name: "Source deck")
        let targetCollection = CardCollection(name: "Target collection")
        let targetDeck = Deck(name: "Target deck")
        context.insert(sourceCollection)
        context.insert(sourceDeck)
        let item = makeItem()
        if sourceKind == 1 { item.collection = sourceCollection }
        if sourceKind == 2 { item.deck = sourceDeck }
        context.insert(item)
        try context.save()
        let sourceID = item.id
        let destination: MoveDestination = targetKind == 0 ? .collection(targetCollection) : .deck(targetDeck)
        let result = try CardTransfer.perform(rows: [CardTransferRow(item: item)], operation: operation,
                                              destination: destination, context: context)
        let transferred = try XCTUnwrap(destination.items.first)
        XCTAssertEqual(transferred.quantity, 4)
        XCTAssertEqual(transferred.scryfallId, "sol-ring-c21")
        XCTAssertEqual(transferred.priceRetail, "$2.00")
        XCTAssertEqual(destination.items.count, 1)
        XCTAssertEqual(transferred.collection?.id, targetKind == 0 ? targetCollection.id : nil)
        XCTAssertEqual(transferred.deck?.id, targetKind == 1 ? targetDeck.id : nil)
        if operation == .copy {
            XCTAssertNotEqual(transferred.id, sourceID)
            XCTAssertEqual(item.quantity, 4)
            XCTAssertEqual(item.collection?.id, sourceKind == 1 ? sourceCollection.id : nil)
            XCTAssertEqual(item.deck?.id, sourceKind == 2 ? sourceDeck.id : nil)
            XCTAssertTrue(result.removedSourceIDs.isEmpty)
        } else {
            XCTAssertEqual(transferred.id, sourceID)
            XCTAssertEqual(result.removedSourceIDs, [sourceID])
        }
        XCTAssertEqual(result.destinationName, destination.name)
        XCTAssertEqual(result.operation, operation)
    }

    func testPartialMoveLeavesRemainderAndUpdatesBothTimestamps() throws {
        let context = try makeContext()
        let source = Deck(name: "Source")
        let target = CardCollection(name: "Target")
        let oldDate = Date(timeIntervalSince1970: 1)
        source.updatedAt = oldDate
        target.updatedAt = oldDate
        context.insert(source)
        context.insert(target)
        let item = makeItem()
        item.deck = source
        context.insert(item)
        var row = CardTransferRow(item: item)
        row.quantity = 2
        let result = try CardTransfer.perform(rows: [row], operation: .move,
                                              destination: .collection(target), context: context)
        XCTAssertEqual(item.quantity, 2)
        XCTAssertEqual(source.items.map(\.id), [item.id])
        XCTAssertEqual(target.items.first?.quantity, 2)
        XCTAssertNotEqual(target.items.first?.id, item.id)
        XCTAssertTrue(result.removedSourceIDs.isEmpty)
        XCTAssertGreaterThan(source.updatedAt, oldDate)
        XCTAssertGreaterThan(target.updatedAt, oldDate)
    }

    func testPartialCopyLeavesSourceQuantityUnchanged() throws {
        let context = try makeContext()
        let item = makeItem()
        context.insert(item)
        let target = Deck(name: "Target")
        var row = CardTransferRow(item: item)
        row.quantity = 1
        _ = try CardTransfer.perform(rows: [row], operation: .copy,
                                     destination: .deck(target), context: context)
        XCTAssertEqual(item.quantity, 4)
        XCTAssertNil(item.collection)
        XCTAssertNil(item.deck)
        XCTAssertEqual(target.items.first?.quantity, 1)
    }

    func testCopyAndMoveMergeMatchingRowsIncludingWithinBatch() throws {
        for operation in CardTransferOperation.allCases {
            let context = try makeContext()
            let target = Deck(name: "Target")
            context.insert(target)
            let existing = makeItem(quantity: 3)
            existing.deck = target
            context.insert(existing)
            let first = makeItem(quantity: 2)
            let second = makeItem(quantity: 4)
            context.insert(first)
            context.insert(second)
            let ids = Set([first.id, second.id])
            let result = try CardTransfer.perform(
                rows: [first, second].map { CardTransferRow(item: $0) }, operation: operation,
                destination: .deck(target), context: context
            )
            XCTAssertEqual(target.items.count, 1)
            XCTAssertEqual(existing.quantity, 9)
            XCTAssertEqual(result.removedSourceIDs, operation == .move ? ids : [])
            let allItems = try context.fetch(FetchDescriptor<CollectionItem>())
            XCTAssertEqual(allItems.count, operation == .move ? 1 : 3)
        }
    }

    func testBatchMergesWithoutPreexistingDestinationRow() throws {
        for operation in CardTransferOperation.allCases {
            let context = try makeContext()
            let first = makeItem(quantity: 2)
            let second = makeItem(quantity: 3)
            context.insert(first)
            context.insert(second)
            let target = CardCollection(name: "Target")
            _ = try CardTransfer.perform(rows: [first, second].map { CardTransferRow(item: $0) },
                                         operation: operation, destination: .collection(target), context: context)
            XCTAssertEqual(target.items.count, 1)
            XCTAssertEqual(target.items.first?.quantity, 5)
        }
    }

    func testPartialMoveMergesWithExistingDestination() throws {
        let context = try makeContext()
        let source = makeItem()
        let target = Deck(name: "Target")
        let existing = makeItem(quantity: 2)
        context.insert(source)
        context.insert(target)
        existing.deck = target
        context.insert(existing)
        var row = CardTransferRow(item: source)
        row.quantity = 3
        _ = try CardTransfer.perform(rows: [row], operation: .move,
                                     destination: .deck(target), context: context)
        XCTAssertEqual(source.quantity, 1)
        XCTAssertEqual(existing.quantity, 5)
        XCTAssertEqual(target.items.count, 1)
    }

    func testFoilAndDifferentPrintingsStaySeparate() throws {
        let context = try makeContext()
        let target = Deck(name: "Target")
        context.insert(target)
        let existing = makeItem()
        existing.deck = target
        context.insert(existing)
        let foil = makeItem(foil: true)
        let differentPrinting = makeItem()
        differentPrinting.scryfallId = "another-printing"
        context.insert(foil)
        context.insert(differentPrinting)
        _ = try CardTransfer.perform(rows: [foil, differentPrinting].map { CardTransferRow(item: $0) },
                                     operation: .move, destination: .deck(target), context: context)
        XCTAssertEqual(target.items.count, 3)
        XCTAssertEqual(existing.quantity, 4)
        XCTAssertTrue(target.items.contains { $0.foil })
    }

    func testStaleQuantityRejectsEntireBatchWithoutCreatingDestination() throws {
        let context = try makeContext()
        let first = makeItem()
        let second = makeItem()
        context.insert(first)
        context.insert(second)
        let rows = [first, second].map { CardTransferRow(item: $0) }
        second.quantity = 2
        let target = Deck(name: "New deck")
        XCTAssertThrowsError(try CardTransfer.perform(rows: rows, operation: .move,
                                                      destination: .deck(target), context: context))
        XCTAssertEqual(first.quantity, 4)
        XCTAssertNil(first.deck)
        XCTAssertTrue(target.items.isEmpty)
        XCTAssertNil(target.modelContext)
    }

    func testDeletedAndRelocatedSourcesAreRejected() throws {
        let context = try makeContext()
        let deleted = makeItem()
        context.insert(deleted)
        try context.save()
        let deletedRow = CardTransferRow(item: deleted)
        context.delete(deleted)
        try context.save()
        let target = Deck(name: "Target")
        XCTAssertThrowsError(try CardTransfer.perform(rows: [deletedRow], operation: .copy,
                                                      destination: .deck(target), context: context))
        let moved = makeItem()
        context.insert(moved)
        let movedRow = CardTransferRow(item: moved)
        let source = CardCollection(name: "Changed source")
        context.insert(source)
        moved.collection = source
        XCTAssertThrowsError(try CardTransfer.perform(rows: [movedRow], operation: .move,
                                                      destination: .deck(target), context: context))
        XCTAssertTrue(target.items.isEmpty)
    }

    func testInvalidRequestsDoNotMutateSources() throws {
        let context = try makeContext()
        let source = makeItem()
        context.insert(source)
        let target = Deck(name: "Target")
        for quantity in [0, -1, 5] {
            var row = CardTransferRow(item: source)
            row.quantity = quantity
            XCTAssertThrowsError(try CardTransfer.perform(rows: [row], operation: .move,
                                                          destination: .deck(target), context: context))
        }
        let row = CardTransferRow(item: source)
        for rows in [[], [row, row]] {
            XCTAssertThrowsError(try CardTransfer.perform(rows: rows, operation: .copy,
                                                          destination: .deck(target), context: context))
        }
        XCTAssertEqual(source.quantity, 4)
        XCTAssertTrue(target.items.isEmpty)
    }

    func testSameSourceDestinationIsRejectedForBothOperations() throws {
        let context = try makeContext()
        let target = Deck(name: "Same deck")
        context.insert(target)
        let source = makeItem()
        source.deck = target
        context.insert(source)
        for operation in CardTransferOperation.allCases {
            XCTAssertThrowsError(try CardTransfer.perform(rows: [CardTransferRow(item: source)],
                                                          operation: operation, destination: .deck(target),
                                                          context: context))
        }
        XCTAssertEqual(source.quantity, 4)
        XCTAssertEqual(target.items.count, 1)
    }

    func testLegacyZeroQuantityTransfersAsOneCard() throws {
        let context = try makeContext()
        let source = makeItem(quantity: 0)
        context.insert(source)
        let target = Deck(name: "Target")
        let row = CardTransferRow(item: source)
        XCTAssertEqual(row.quantity, 1)
        _ = try CardTransfer.perform(rows: [row], operation: .move,
                                     destination: .deck(target), context: context)
        XCTAssertEqual(target.items.first?.quantity, 1)
    }
}
