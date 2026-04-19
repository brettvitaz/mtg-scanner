import MTGScannerKit
import SwiftData
import SwiftUI

/// Snapshot-test fixture that renders ResultsView with one card per rarity tier.
public struct ResultsFixtureView: View {
    private static let container: ModelContainer = makeContainer()

    @State private var appModel = AppModel()

    public init() {}

    public var body: some View {
        NavigationStack {
            ResultsView()
        }
        .environment(appModel)
        .modelContainer(Self.container)
    }
}

private func makeContainer() -> ModelContainer {
    let schema = Schema([CollectionItem.self, CardCollection.self, Deck.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(for: schema, configurations: [config])
    let ctx = ModelContext(container)
    for item in makeFixtureItems() { ctx.insert(item) }
    // swiftlint:disable:next force_try
    try! ctx.save()
    return container
}

private func makeFixtureItems() -> [CollectionItem] {
    [mythicItem(), rareItem(), uncommonItem(), commonItem()]
}

private func mythicItem() -> CollectionItem {
    CollectionItem(
        title: "Sheoldred, the Apocalypse",
        edition: "Dominaria United",
        setCode: "DMU",
        collectorNumber: "107",
        rarity: "mythic",
        priceRetail: "$34.99",
        priceBuy: "$28.00",
        addedAt: Date(timeIntervalSinceNow: -4)
    )
}

private func rareItem() -> CollectionItem {
    CollectionItem(
        title: "The One Ring",
        edition: "The Lord of the Rings",
        setCode: "LTR",
        collectorNumber: "246",
        foil: true,
        rarity: "rare",
        priceRetail: "$12.45",
        priceBuy: "$9.10",
        addedAt: Date(timeIntervalSinceNow: -3)
    )
}

private func uncommonItem() -> CollectionItem {
    CollectionItem(
        title: "Counterspell",
        edition: "Magic 2014",
        setCode: "M14",
        collectorNumber: "54",
        rarity: "uncommon",
        priceRetail: "$1.20",
        priceBuy: "$0.80",
        addedAt: Date(timeIntervalSinceNow: -2)
    )
}

private func commonItem() -> CollectionItem {
    CollectionItem(
        title: "Island",
        edition: "Foundations",
        setCode: "FDN",
        collectorNumber: "280",
        rarity: "common",
        priceRetail: "$0.15",
        addedAt: Date(timeIntervalSinceNow: -1)
    )
}
