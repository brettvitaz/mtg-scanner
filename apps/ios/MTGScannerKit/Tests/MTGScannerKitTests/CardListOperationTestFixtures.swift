import SwiftData
import XCTest
@testable import MTGScannerKit

@MainActor
enum CardListOperationTestFixtures {
    static func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: CollectionItem.self, CardCollection.self, Deck.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    static func list(_ kind: CardListKind = .collection, name: String = "Target") -> CardListReference {
        switch kind {
        case .collection: .collection(CardCollection(name: name))
        case .deck: .deck(Deck(name: name))
        }
    }

    @discardableResult
    static func item(
        _ quantity: Int, id: String? = "bolt", foil: Bool = false,
        in list: CardListReference? = nil, context: ModelContext? = nil
    ) -> CollectionItem {
        let item = CollectionItem(
            title: "Lightning Bolt", edition: "Magic 2010", collectorNumber: "146",
            foil: foil, oracleText: "Deal 3 damage.", scryfallId: id,
            priceRetail: "1.00", priceBuy: "0.50", qtyBuying: 20, quantity: quantity
        )
        list?.assign(item)
        context?.insert(item)
        return item
    }

    static func plan(
        target: CardListReference, tool: CardListReference, operation: CardListOperation = .subtract,
        deleteTool: Bool = false
    ) throws -> CardListOperationPlan {
        try CardListOperationPlanner().plan(
            target: target.snapshot(), toolItems: tool.items.map(CardItemSnapshot.init), toolName: tool.name,
            operation: operation, tool: tool.snapshot(), deleteTool: deleteTool
        )
    }
}
