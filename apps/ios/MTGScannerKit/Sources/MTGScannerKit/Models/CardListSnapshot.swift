import Foundation

struct CardItemSnapshot: Equatable, Identifiable {
    var id: UUID
    let card: RecognizedCard
    let priceRetail: String?
    let priceBuy: String?
    let qtyBuying: Int?
    let addedAt: Date
    var quantity: Int

    init(_ item: CollectionItem) {
        id = item.id
        card = item.toRecognizedCard()
        priceRetail = item.priceRetail
        priceBuy = item.priceBuy
        qtyBuying = item.qtyBuying
        addedAt = item.addedAt
        quantity = item.quantity
    }

    func matches(_ other: Self) -> Bool {
        guard card.foil == other.card.foil else { return false }
        if let lhs = card.scryfallId?.nonEmpty, let rhs = other.card.scryfallId?.nonEmpty {
            return lhs == rhs
        }
        return card.title == other.card.title && card.edition == other.card.edition
            && card.collectorNumber == other.card.collectorNumber
    }

    func hasSameInventory(as other: Self) -> Bool {
        id == other.id && quantity == other.quantity && card.foil == other.card.foil
            && card.scryfallId == other.card.scryfallId && card.title == other.card.title
            && card.edition == other.card.edition && card.setCode == other.card.setCode
            && card.collectorNumber == other.card.collectorNumber
    }

    private var printingMetadata: [String?] {
        [card.title, card.edition, card.setCode, card.collectorNumber, card.scryfallId,
         card.rarity, card.typeLine, card.oracleText, card.manaCost, card.power, card.toughness,
         card.loyalty, card.defense, card.imageUrl, card.setSymbolUrl, card.cardKingdomUrl, card.colorIdentity]
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.quantity == rhs.quantity && lhs.addedAt == rhs.addedAt
            && lhs.card.foil == rhs.card.foil && lhs.printingMetadata == rhs.printingMetadata
            && lhs.priceRetail == rhs.priceRetail && lhs.priceBuy == rhs.priceBuy && lhs.qtyBuying == rhs.qtyBuying
    }

    func makeItem() -> CollectionItem {
        let item = CollectionItem(from: card)
        item.id = id
        item.priceRetail = priceRetail
        item.priceBuy = priceBuy
        item.qtyBuying = qtyBuying
        item.addedAt = addedAt
        item.quantity = quantity
        return item
    }
}

struct CardListSnapshot: Equatable {
    let id: UUID
    let kind: CardListKind
    let name: String
    let createdAt: Date
    var updatedAt: Date
    var items: [CardItemSnapshot]

    func hasSameInventory(as other: Self) -> Bool {
        id == other.id && kind == other.kind && name == other.name && items.count == other.items.count
            && zip(items, other.items).allSatisfy { $0.hasSameInventory(as: $1) }
    }
}

enum CardListKind: String {
    case collection = "Collection"
    case deck = "Deck"
}
