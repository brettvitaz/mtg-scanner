import SwiftData
import SwiftUI
import ViewInspector
import XCTest
@testable import MTGScannerKit

@MainActor
final class CardTransferInteractionTests: XCTestCase {
    func testBulkButtonsPassDistinctOperationsAndDisableEmptySelection() throws {
        var operations: [CardTransferOperation] = []
        let bar = CardSelectionActionBar(isEmpty: false, onTransfer: { operations.append($0) }, onDelete: {})
        try bar.inspect().find(button: "Copy…").tap()
        try bar.inspect().find(button: "Move…").tap()
        XCTAssertEqual(operations, [.copy, .move])
        let empty = CardSelectionActionBar(isEmpty: true, onTransfer: { operations.append($0) }, onDelete: {})
        XCTAssertThrowsError(try empty.inspect().find(button: "Copy…").tap())
        XCTAssertThrowsError(try empty.inspect().find(button: "Move…").tap())
        XCTAssertEqual(operations, [.copy, .move])
    }

    func testDestinationVoiceOverLabelDistinguishesCollectionAndDeckWithSameName() throws {
        let model = CardTransferViewModel(items: [], operation: .copy)
        let sheet = CardTransferSheet(model: model) { _ in }
        model.select(.collection(CardCollection(name: "Favorites")))
        var button = try sheet.inspect().find(ViewType.Button.self) {
            try $0.accessibilityLabel().string().hasPrefix("Destination,")
        }
        XCTAssertEqual(try button.accessibilityLabel().string(), "Destination, Favorites, Collection")
        model.select(.deck(Deck(name: "Favorites")))
        button = try sheet.inspect().find(ViewType.Button.self) {
            try $0.accessibilityLabel().string().hasPrefix("Destination,")
        }
        XCTAssertEqual(try button.accessibilityLabel().string(), "Destination, Favorites, Deck")
    }

    func testConfirmationButtonAloneTransfersAndCompletes() throws {
        for operation in CardTransferOperation.allCases {
            let context = try context()
            let source = CollectionItem(title: "Island", edition: "Test", quantity: 4)
            context.insert(source)
            try context.save()
            let model = CardTransferViewModel(items: [source], operation: operation)
            var completions = 0
            let sheet = CardTransferSheet(model: model) { _ in completions += 1 }
                .environment(\.modelContext, context)
            XCTAssertThrowsError(try sheet.inspect().find(button: operation.rawValue).tap())
            model.select(.deck(Deck(name: "Draft")))
            model.setQuantity(2, for: source.id)
            XCTAssertEqual(completions, 0)
            XCTAssertTrue(try context.fetch(FetchDescriptor<Deck>()).isEmpty)
            try sheet.inspect().find(button: operation.rawValue).tap()
            XCTAssertEqual(completions, 1)
            XCTAssertEqual(source.quantity, operation == .copy ? 4 : 2)
            XCTAssertEqual(try context.fetch(FetchDescriptor<Deck>()).first?.items.totalQuantity, 2)
            XCTAssertTrue(model.isDismissed)
        }
    }

    func testVoiceOverRowActionsPassDistinctOperations() throws {
        var operations: [CardTransferOperation] = []
        let row = CollectionItemRow(
            item: CollectionItem(title: "Island", edition: "Test"),
            onTransfer: { operations.append($0) }
        )
        try row.accessibilityButtons.inspect().find(button: "Copy…").tap()
        try row.accessibilityButtons.inspect().find(button: "Move…").tap()
        XCTAssertEqual(operations, [.copy, .move])
    }

    func testSavedDetailButtonsPresentMatchingOperationsWithoutTransferring() throws {
        let context = try context()
        let source = CollectionItem(title: "Island", edition: "Test", quantity: 4)
        context.insert(source)
        try context.save()
        let model = CardDetailViewModel(card: source.toRecognizedCard(), cropImage: nil)
        let view = CardDetailView(viewModel: model)
            .environment(AppModel()).environment(\.modelContext, context)
        try view.inspect().find(button: "Copy…").tap()
        XCTAssertEqual(model.transferOperation, .copy)
        try view.inspect().find(button: "Move…").tap()
        XCTAssertEqual(model.transferOperation, .move)
        XCTAssertEqual(source.quantity, 4)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectionItem>()), 1)
    }

    func testCancelControlAndSwipeDisappearanceDoNotTransferOrComplete() throws {
        for swipe in [false, true] {
            let context = try context()
            let source = CollectionItem(title: "Island", edition: "Test", quantity: 4)
            context.insert(source)
            try context.save()
            let model = CardTransferViewModel(items: [source], operation: .move)
            model.select(.deck(Deck(name: "Draft")))
            let sheet = CardTransferSheet(model: model) { _ in XCTFail("Cancelled transfer completed") }
                .environment(\.modelContext, context)
            if swipe {
                try sheet.inspect().find(ViewType.NavigationStack.self).callOnDisappear()
            } else {
                try sheet.inspect().find(button: "Cancel").tap()
            }
            XCTAssertTrue(model.isDismissed)
            XCTAssertEqual(source.quantity, 4)
            XCTAssertTrue(try context.fetch(FetchDescriptor<Deck>()).isEmpty)
        }
    }

    func testPickerCreationCallbacksKeepNewDestinationsAsDrafts() throws {
        let context = try context()
        let source = CollectionItem(title: "Island", edition: "Test", quantity: 4)
        context.insert(source)
        try context.save()
        let model = CardTransferViewModel(items: [source], operation: .copy)
        let picker = CardTransferDestinationPicker(model: model).environment(\.modelContext, context)
        let sections = try picker.inspect().find(CardDestinationSections.self).actualView()
        model.showDestinations()
        sections.createCollection(named: "Draft collection")
        XCTAssertEqual(model.destination?.name, "Draft collection")
        XCTAssertTrue(model.path.isEmpty)
        model.showDestinations()
        sections.createDeck(named: "Draft deck")
        XCTAssertEqual(model.destination?.name, "Draft deck")
        XCTAssertTrue(model.path.isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CardCollection>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Deck>()).isEmpty)
        XCTAssertEqual(source.quantity, 4)
    }

    private func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: CollectionItem.self, CardCollection.self, Deck.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }
}
