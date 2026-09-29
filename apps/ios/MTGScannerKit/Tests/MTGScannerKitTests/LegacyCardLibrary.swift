import Foundation
import SwiftData

// Exact stored fields from the pre-availability schema, retained to exercise migration.
enum LegacyCardLibrary {
    @Model
    final class CollectionItem {
        var id: UUID
        var title: String
        var edition: String
        var setCode: String?
        var collectorNumber: String?
        var foil: Bool
        var rarity: String?
        var typeLine: String?
        var oracleText: String?
        var manaCost: String?
        var power: String?
        var toughness: String?
        var loyalty: String?
        var defense: String?
        var scryfallId: String?
        var imageUrl: String?
        var setSymbolUrl: String?
        var cardKingdomUrl: String?
        var colorIdentity: String?
        var priceRetail: String?
        var priceBuy: String?
        var addedAt: Date
        var quantity: Int

        @Relationship(inverse: \CardCollection.items)
        var collection: CardCollection?

        @Relationship(inverse: \Deck.items)
        var deck: Deck?

        init(title: String, quantity: Int) {
            id = UUID()
            self.title = title
            edition = "Magic 2010"
            foil = false
            addedAt = Date()
            self.quantity = quantity
        }

    }

    @Model
    final class CardCollection {
        var id: UUID
        var name: String
        @Relationship(deleteRule: .cascade)
        var items: [CollectionItem]
        var createdAt: Date
        var updatedAt: Date

        init(name: String) {
            self.id = UUID()
            self.name = name
            self.items = []
            self.createdAt = Date()
            self.updatedAt = Date()
        }
    }

    @Model
    final class Deck {
        var id: UUID
        var name: String
        @Relationship(deleteRule: .cascade)
        var items: [CollectionItem]
        var createdAt: Date
        var updatedAt: Date

        init(name: String) {
            self.id = UUID()
            self.name = name
            self.items = []
            self.createdAt = Date()
            self.updatedAt = Date()
        }
    }

}
