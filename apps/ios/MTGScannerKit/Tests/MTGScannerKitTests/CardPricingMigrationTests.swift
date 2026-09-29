import SwiftData
import XCTest
@testable import MTGScannerKit

@MainActor
final class CardPricingMigrationTests: XCTestCase {
    func testExistingStoreMigratesAndPreservesCollectionsDecksAndPrices() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "library.store")
        try writeLegacyStore(at: url)
        let schema = Schema([CollectionItem.self, CardCollection.self, Deck.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let items = try container.mainContext.fetch(FetchDescriptor<CollectionItem>())
        XCTAssertEqual(items.count, 2)
        let binder = try XCTUnwrap(items.first { $0.collection != nil })
        XCTAssertEqual(binder.collection?.name, "Binder")
        XCTAssertEqual(binder.quantity, 4)
        XCTAssertEqual(binder.priceBuy, "$0.50")
        XCTAssertNil(binder.qtyBuying)
        XCTAssertEqual(items.first { $0.deck != nil }?.deck?.name, "Deck")
        binder.qtyBuying = 3
        try container.mainContext.save()
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<CardCollection>()).first?.items.count, 1)
    }

    private func writeLegacyStore(at url: URL) throws {
        let schema = Schema([LegacyCardLibrary.CollectionItem.self,
                             LegacyCardLibrary.CardCollection.self, LegacyCardLibrary.Deck.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let binder = LegacyCardLibrary.CardCollection(name: "Binder")
        let deck = LegacyCardLibrary.Deck(name: "Deck")
        let card = LegacyCardLibrary.CollectionItem(title: "Lightning Bolt", quantity: 4)
        card.priceBuy = "$0.50"
        card.priceRetail = "$2.00"
        card.collection = binder
        let deckCard = LegacyCardLibrary.CollectionItem(title: "Forest", quantity: 2)
        deckCard.deck = deck
        container.mainContext.insert(binder)
        container.mainContext.insert(deck)
        container.mainContext.insert(card)
        container.mainContext.insert(deckCard)
        try container.mainContext.save()
    }
}
