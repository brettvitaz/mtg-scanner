import SwiftData
import XCTest
@testable import MTGScannerKit

@MainActor
final class ResultEvidenceOwnershipTests: XCTestCase {
    func testCopyFullAndPartialMoveWithAndWithoutMergeKeepEvidenceOnlyOnResults() throws {
        let quantitiesAndMerges = [(false, false), (false, true), (true, false), (true, true)]
        for operation in CardTransferOperation.allCases {
            for (partial, merge) in quantitiesAndMerges {
                for useDeck in [false, true] {
                    try checkTransfer(operation, partial: partial, merge: merge, useDeck: useDeck)
                }
            }
        }
    }

    private func checkTransfer(_ operation: CardTransferOperation, partial: Bool, merge: Bool, useDeck: Bool) throws {
        let context = try context()
        let item = CollectionItem(title: "Island", edition: "Test", quantity: 4)
        item.resultScanJPEG = Data([1, 2, 3])
        item.originalRecognition = Data([4, 5, 6])
        context.insert(item)
        let destination: MoveDestination = useDeck
            ? .deck(Deck(name: "Deck")) : .collection(CardCollection(name: "Binder"))
        destination.insertIfNeeded(in: context)
        if merge {
            let existing = item.duplicate()
            destination.assign(existing)
            context.insert(existing)
        }
        var row = CardTransferRow(item: item)
        row.quantity = partial ? 2 : 4
        let result = try CardTransfer.perform(rows: [row], operation: operation,
                                              destination: destination, context: context)
        let target = try XCTUnwrap(destination.items.first)
        XCTAssertNil(target.resultScanJPEG)
        XCTAssertNil(target.originalRecognition)
        XCTAssertNil(target.resultScanImage)
        if operation == .copy || partial {
            XCTAssertTrue(result.removedSourceIDs.isEmpty)
            XCTAssertEqual(item.resultScanJPEG, Data([1, 2, 3]))
            XCTAssertEqual(item.originalRecognition, Data([4, 5, 6]))
        } else {
            XCTAssertEqual(result.removedSourceIDs, [item.id])
            let allItems = try context.fetch(FetchDescriptor<CollectionItem>())
            let results = allItems.filter { $0.collection == nil && $0.deck == nil }
            XCTAssertTrue(results.isEmpty)
        }
    }

    func testDeleteUndoRestoresEvidenceFromSnapshot() throws {
        let context = try context()
        let item = CollectionItem(title: "Island", edition: "Test")
        item.resultScanJPEG = Data([1, 2, 3])
        item.originalRecognition = Data([4, 5, 6])
        context.insert(item)
        try context.save()
        let id = item.id
        let undo = CardDeleteUndoStore()
        undo.register([item], in: .results)
        let deletion = try XCTUnwrap(undo.deletion(in: .results))
        context.delete(item)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectionItem>()), 0)
        try undo.restore(in: .results, deletionID: deletion.id, context: context, commit: { try context.save() })
        let restored = try XCTUnwrap(context.fetch(FetchDescriptor<CollectionItem>()).first)
        XCTAssertEqual(restored.id, id)
        XCTAssertEqual(restored.resultScanJPEG, Data([1, 2, 3]))
        XCTAssertEqual(restored.originalRecognition, Data([4, 5, 6]))
    }

    private func context() throws -> ModelContext {
        let container = try ModelContainer(for: CollectionItem.self, CardCollection.self, Deck.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
}
