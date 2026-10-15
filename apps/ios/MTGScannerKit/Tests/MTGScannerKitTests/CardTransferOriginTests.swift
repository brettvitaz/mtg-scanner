import SwiftData
import SwiftUI
import ViewInspector
import XCTest
@testable import MTGScannerKit

@MainActor
final class CardTransferOriginTests: XCTestCase {
    func testEveryOriginBulkButtonsPresentMatchingOperationsAndDisableEmptySelection() throws {
        let context = try context()
        for origin in 0..<3 {
            let selection = CardListSelectionState()
            selection.isSelecting = true
            selection.selectedItems = [UUID()]
            for (title, operation) in [("Copy…", CardTransferOperation.copy), ("Move…", .move)] {
                let bar = bulkBar(origin, selection: selection, context: context)
                try bar.inspect().find(button: title).tap()
                XCTAssertEqual(selection.transferRequest?.operation, operation)
                XCTAssertEqual(selection.transferRequest?.isBulk, true)
                XCTAssertTrue(selection.isSelecting)
            }
            selection.transferRequest = nil
            selection.selectedItems = []
            let emptyBar = bulkBar(origin, selection: selection, context: context)
            XCTAssertThrowsError(try emptyBar.inspect().find(button: "Copy…").tap())
            XCTAssertThrowsError(try emptyBar.inspect().find(button: "Move…").tap())
            XCTAssertNil(selection.transferRequest)
        }
    }

    func testEveryOriginPreservesSelectionOnCancelAndDismissal() throws {
        let context = try context()
        let source = CollectionItem(title: "Island", edition: "Test", quantity: 4)
        context.insert(source)
        try context.save()
        for origin in 0..<3 {
            for swipe in [false, true] {
                let selection = CardListSelectionState()
                selection.isSelecting = true
                selection.selectedItems = [source.id]
                selection.transferRequest = CardTransferRequest(items: [source], operation: .move, isBulk: true)
                let view = view(origin, selection: selection, context: context)
                if !swipe { try view.inspect().find(button: "Cancel").tap() }
                try view.inspect().find(ViewType.Sheet.self).dismiss()
                XCTAssertNil(selection.transferRequest)
                XCTAssertTrue(selection.isSelecting)
                XCTAssertEqual(selection.selectedItems, [source.id])
                XCTAssertEqual(source.quantity, 4)
            }
        }
    }

    func testEveryOriginClearsSelectionOnlyOnSuccessfulBulkCompletion() throws {
        let context = try context()
        let source = CollectionItem(title: "Island", edition: "Test", quantity: 4)
        context.insert(source)
        try context.save()
        for origin in 0..<3 {
            for bulk in [false, true] {
                let selection = CardListSelectionState()
                selection.isSelecting = true
                selection.selectedItems = [source.id]
                selection.transferRequest = CardTransferRequest(items: [source], operation: .copy, isBulk: bulk)
                let view = view(origin, selection: selection, context: context)
                let sheet = try view.inspect().find(CardTransferSheet.self).actualView()
                sheet.onComplete(CardTransferResult(operation: .copy, destinationName: "Target", removedSourceIDs: []))
                XCTAssertEqual(selection.isSelecting, !bulk)
                XCTAssertEqual(selection.selectedItems, bulk ? [] : [source.id])
            }
        }
    }

    private func view(_ origin: Int, selection: CardListSelectionState, context: ModelContext) -> AnyView {
        let view: AnyView
        switch origin {
        case 0: view = AnyView(ResultsView(selection: selection))
        case 1:
            let collection = CardCollection(name: "Source")
            context.insert(collection)
            view = AnyView(CollectionDetailView(collection: collection, selection: selection))
        default:
            let deck = Deck(name: "Source")
            context.insert(deck)
            view = AnyView(DeckDetailView(deck: deck, selection: selection))
        }
        return AnyView(view.environment(AppModel()).environment(\.modelContext, context))
    }

    private func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: CollectionItem.self, CardCollection.self, Deck.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func bulkBar(_ origin: Int, selection: CardListSelectionState, context: ModelContext) -> AnyView {
        switch origin {
        case 0: return AnyView(ResultsView(selection: selection).bottomActionBar)
        case 1:
            let collection = CardCollection(name: "Source")
            context.insert(collection)
            return AnyView(CollectionDetailView(collection: collection, selection: selection).bottomActionBar)
        default:
            let deck = Deck(name: "Source")
            context.insert(deck)
            return AnyView(DeckDetailView(deck: deck, selection: selection).bottomActionBar)
        }
    }
}
