#if DEBUG
import SwiftData
import SwiftUI

/// Seeds shared state once, then presents the production transfer navigation unchanged.
public struct CardTransferFixtureView: View {
    @State private var model: CardTransferViewModel
    @State private var isPresented = true
    private let container: ModelContainer?
    private let setupError: String?

    public init(route: String) {
        let items = (1...30).map { index in
            CollectionItem(
                title: "Card \(index): A long card name for quantity review",
                edition: "Commander 2017", collectorNumber: String(index),
                foil: index.isMultiple(of: 3), quantity: 5
            )
        }
        let model = CardTransferViewModel(items: items, operation: route == "move-cards" ? .move : .copy)
        do {
            let container = try Self.container(items: items, empty: route == "transfer-destinations-empty")
            // Construct rows after assigning the source relationships, so exclusion uses real source IDs.
            let seeded = CardTransferViewModel(items: items, operation: model.operation)
            if route == "move-cards" {
                let decks = try container.mainContext.fetch(FetchDescriptor<Deck>())
                if let target = decks.first(where: { seeded.destinationFilter.includes(.deck($0)) }) {
                    seeded.select(.deck(target))
                }
                for item in items { seeded.setQuantity(2, for: item.id) }
            }
            if route.hasPrefix("transfer-destinations") { seeded.path = [.destinations] }
            if route == "transfer-quantities" {
                for item in items { seeded.setQuantity(2, for: item.id) }
                seeded.path = [.quantities]
            }
            if route == "transfer-error" {
                seeded.select(.deck(Deck(name: "New draft deck")))
                items[0].quantity = 1
                try container.mainContext.save()
                seeded.submit(in: container.mainContext) { _ in }
            }
            _model = State(initialValue: seeded)
            self.container = container
            setupError = nil
        } catch {
            _model = State(initialValue: model)
            container = nil
            setupError = error.localizedDescription
        }
    }

    public var body: some View {
        if let container {
            Text("Card Transfer")
                .sheet(isPresented: $isPresented) { CardTransferSheet(model: model) { _ in } }
                .modelContainer(container)
        } else {
            Text(setupError ?? "Unable to load transfer fixture.")
        }
    }

    private static func container(items: [CollectionItem], empty: Bool) throws -> ModelContainer {
        let container = try ModelContainer(
            for: CollectionItem.self, CardCollection.self, Deck.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let collection = CardCollection(name: "Excluded source collection")
        let deck = Deck(name: "Excluded source deck")
        context.insert(collection)
        context.insert(deck)
        for (index, item) in items.enumerated() {
            if index.isMultiple(of: 2) { item.collection = collection } else { item.deck = deck }
            context.insert(item)
        }
        if !empty {
            for index in 1...15 {
                context.insert(CardCollection(name: "Collection \(index): A long destination name for wrapping"))
                context.insert(Deck(name: "Deck \(index): A long Commander deck name for wrapping"))
            }
        }
        try context.save()
        return container
    }
}
#endif
