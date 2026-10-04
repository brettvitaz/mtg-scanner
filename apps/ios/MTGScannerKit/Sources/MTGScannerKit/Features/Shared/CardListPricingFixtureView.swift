#if DEBUG
import SwiftData
import SwiftUI

/// Fixture routes for totals and CK availability using the production list screens.
public struct CardListPricingFixtureView: View {
    @State private var filterState = CardFilterState()
    private let fixtureItems: [CollectionItem]
    private let route: String
    private let collection = CardCollection(name: "Trade Binder")
    private let deck = Deck(name: "Commander Deck")
    private let appModel = AppModel()
    private let container: ModelContainer?
    private let setupError: String?

    public init(route: String) {
        self.route = route
        fixtureItems = route.hasPrefix("card-row-") ? Self.previewItems() : Self.items(large: route == "pricing-large")
        do {
            let container = try ModelContainer(
                for: CollectionItem.self, CardCollection.self, Deck.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            container.mainContext.insert(collection)
            container.mainContext.insert(deck)
            for item in fixtureItems {
                if route == "pricing-collection" || route == "copy-move" || route == "card-row-list" {
                    item.collection = collection
                }
                if route == "pricing-deck" { item.deck = deck }
                container.mainContext.insert(item)
            }
            try container.mainContext.save()
            self.container = container
            setupError = nil
        } catch {
            container = nil
            setupError = error.localizedDescription
        }
    }

    public var body: some View {
        if let container {
            content.modelContainer(container).environment(appModel)
        } else {
            Text(setupError ?? "Unable to load pricing fixture.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case "pricing-collection", "card-row-list": NavigationStack { CollectionDetailView(collection: collection) }
        case "pricing-deck": NavigationStack { DeckDetailView(deck: deck) }
        case "copy-move": CopyMoveSheet(items: fixtureItems) { _ in }
        case "card-row-preview":
            GeometryReader { geometry in
                let size = CardRowPreview.size(in: geometry.size)
                CardRowPreview(item: fixtureItems[0])
                    .frame(width: size.width, height: size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.dsBackground)
            }
        case "pricing-filter": FilterSheet(filterState: filterState, items: fixtureItems)
        default: ResultsView()
        }
    }

    private static func previewItems() -> [CollectionItem] {
        [
            CollectionItem(title: "Teferi’s Protection", edition: "Commander 2017", setCode: "C17",
                           collectorNumber: "8", foil: true, rarity: "rare",
                           imageUrl: "https://fixtures.invalid/card-preview.jpg",
                           priceRetail: "$34.99", priceBuy: "$28.00", quantity: 2),
            CollectionItem(title: "A very long card name to check wrapping without artwork",
                           edition: "A long edition name for preview layout checks", quantity: 1)
        ]
    }

    private static func items(large: Bool) -> [CollectionItem] {
        [
            CollectionItem(title: "Sheoldred, the Apocalypse", edition: "Dominaria United", setCode: "DMU",
                           rarity: "mythic", priceRetail: large ? "$123,456.78" : "$34.99",
                           priceBuy: large ? "$98,765.43" : "$28.00", qtyBuying: 12, quantity: 4),
            CollectionItem(title: "The One Ring", edition: "The Lord of the Rings", setCode: "LTR", foil: true,
                           rarity: "rare", priceRetail: "$12.45", priceBuy: "$9.10", qtyBuying: 0),
            CollectionItem(title: "Counterspell", edition: "Magic 2014", setCode: "M14", rarity: "uncommon",
                           priceRetail: "$1.20", priceBuy: "$0.80", qtyBuying: 5, quantity: 2),
            CollectionItem(title: "Island", edition: "Foundations", setCode: "FDN", rarity: "common",
                           priceRetail: "$0.15")
        ]
    }
}
#endif
