import Foundation
import SwiftData

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
    var addedAt: Date

    @Relationship(inverse: \CardCollection.items)
    var collection: CardCollection?

    @Relationship(inverse: \Deck.items)
    var deck: Deck?

    init(
        title: String,
        edition: String,
        setCode: String? = nil,
        collectorNumber: String? = nil,
        foil: Bool = false,
        rarity: String? = nil,
        typeLine: String? = nil,
        oracleText: String? = nil,
        manaCost: String? = nil,
        power: String? = nil,
        toughness: String? = nil,
        loyalty: String? = nil,
        defense: String? = nil,
        scryfallId: String? = nil,
        imageUrl: String? = nil,
        setSymbolUrl: String? = nil,
        cardKingdomUrl: String? = nil,
        addedAt: Date = Date(),
        collection: CardCollection? = nil,
        deck: Deck? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.edition = edition
        self.setCode = setCode
        self.collectorNumber = collectorNumber
        self.foil = foil
        self.rarity = rarity
        self.typeLine = typeLine
        self.oracleText = oracleText
        self.manaCost = manaCost
        self.power = power
        self.toughness = toughness
        self.loyalty = loyalty
        self.defense = defense
        self.scryfallId = scryfallId
        self.imageUrl = imageUrl
        self.setSymbolUrl = setSymbolUrl
        self.cardKingdomUrl = cardKingdomUrl
        self.addedAt = addedAt
        self.collection = collection
        self.deck = deck
    }

    /// Create a CollectionItem from a recognized card, applying corrections if present.
    convenience init(from card: RecognizedCard, correction: CardCorrection? = nil) {
        self.init(
            title: correction?.title.nonEmpty ?? card.title ?? "Unknown",
            edition: correction?.edition.nonEmpty ?? card.edition ?? "Unknown",
            setCode: card.setCode,
            collectorNumber: correction?.collectorNumber.nonEmpty ?? card.collectorNumber,
            foil: correction?.foil ?? card.foil ?? false,
            rarity: card.rarity,
            typeLine: card.typeLine,
            oracleText: card.oracleText,
            manaCost: card.manaCost,
            power: card.power,
            toughness: card.toughness,
            loyalty: card.loyalty,
            defense: card.defense,
            scryfallId: card.scryfallId,
            imageUrl: card.imageUrl,
            setSymbolUrl: card.setSymbolUrl,
            cardKingdomUrl: card.cardKingdomUrl
        )
    }

    /// Convert to a RecognizedCard for use with CardDetailView.
    func toRecognizedCard() -> RecognizedCard {
        RecognizedCard(
            id: id,
            title: title,
            edition: edition,
            collectorNumber: collectorNumber,
            foil: foil,
            confidence: 1.0,
            setCode: setCode,
            rarity: rarity,
            typeLine: typeLine,
            oracleText: oracleText,
            manaCost: manaCost,
            power: power,
            toughness: toughness,
            loyalty: loyalty,
            defense: defense,
            scryfallId: scryfallId,
            imageUrl: imageUrl,
            setSymbolUrl: setSymbolUrl,
            cardKingdomUrl: cardKingdomUrl
        )
    }

    /// Create a copy of this item (for "Copy to" operations).
    func duplicate() -> CollectionItem {
        CollectionItem(
            title: title,
            edition: edition,
            setCode: setCode,
            collectorNumber: collectorNumber,
            foil: foil,
            rarity: rarity,
            typeLine: typeLine,
            oracleText: oracleText,
            manaCost: manaCost,
            power: power,
            toughness: toughness,
            loyalty: loyalty,
            defense: defense,
            scryfallId: scryfallId,
            imageUrl: imageUrl,
            setSymbolUrl: setSymbolUrl,
            cardKingdomUrl: cardKingdomUrl
        )
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
