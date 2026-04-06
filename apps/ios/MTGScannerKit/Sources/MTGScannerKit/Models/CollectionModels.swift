import Foundation
import SwiftData

@Model
public final class CollectionItem {
    public var id: UUID
    public var title: String
    public var edition: String
    public var setCode: String?
    public var collectorNumber: String?
    public var foil: Bool
    public var rarity: String?
    public var typeLine: String?
    public var oracleText: String?
    public var manaCost: String?
    public var power: String?
    public var toughness: String?
    public var loyalty: String?
    public var defense: String?
    public var scryfallId: String?
    public var imageUrl: String?
    public var setSymbolUrl: String?
    public var cardKingdomUrl: String?
    public var colorIdentity: String?
    public var priceRetail: String?
    public var priceBuy: String?
    public var addedAt: Date
    public var quantity: Int

    @Relationship(inverse: \CardCollection.items)
    public var collection: CardCollection?

    @Relationship(inverse: \Deck.items)
    public var deck: Deck?

    public init(
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
        colorIdentity: String? = nil,
        priceRetail: String? = nil,
        priceBuy: String? = nil,
        addedAt: Date = Date(),
        quantity: Int = 1,
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
        self.colorIdentity = colorIdentity
        self.priceRetail = priceRetail
        self.priceBuy = priceBuy
        self.addedAt = addedAt
        self.quantity = quantity
        self.collection = collection
        self.deck = deck
    }

    /// Create a CollectionItem from a recognized card, applying corrections if present.
    /// When a correction includes a `selectedPrintingSnapshot`, its fields take priority
    /// for image URL, Card Kingdom link, and other printing-specific metadata.
    convenience init(from card: RecognizedCard, correction: CardCorrection? = nil) {
        let printing = correction?.selectedPrintingSnapshot
        self.init(
            title: correction?.title.nonEmpty ?? card.title ?? "Unknown",
            edition: correction?.edition.nonEmpty ?? card.edition ?? "Unknown",
            setCode: printing?.setCode ?? card.setCode,
            collectorNumber: correction?.collectorNumber.nonEmpty ?? card.collectorNumber,
            foil: correction?.foil ?? card.foil ?? false,
            rarity: printing?.rarity ?? card.rarity,
            typeLine: printing?.typeLine ?? card.typeLine,
            oracleText: printing?.oracleText ?? card.oracleText,
            manaCost: printing?.manaCost ?? card.manaCost,
            power: printing?.power ?? card.power,
            toughness: printing?.toughness ?? card.toughness,
            loyalty: printing?.loyalty ?? card.loyalty,
            defense: printing?.defense ?? card.defense,
            scryfallId: printing?.scryfallId ?? card.scryfallId,
            imageUrl: printing?.imageUrl ?? card.imageUrl,
            setSymbolUrl: printing?.setSymbolUrl ?? card.setSymbolUrl,
            cardKingdomUrl: printing?.cardKingdomUrl ?? card.cardKingdomUrl,
            colorIdentity: printing?.colorIdentity ?? card.colorIdentity
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
            cardKingdomUrl: cardKingdomUrl,
            colorIdentity: colorIdentity
        )
    }

    /// Returns true if this item represents the same card as another.
    /// Keyed by scryfallId when available; falls back to (title, edition, collectorNumber, foil).
    func matches(_ other: CollectionItem) -> Bool {
        if let a = scryfallId, let b = other.scryfallId, !a.isEmpty, !b.isEmpty {
            return a == b && foil == other.foil
        }
        return title == other.title
            && edition == other.edition
            && collectorNumber == other.collectorNumber
            && foil == other.foil
    }

    /// Returns true if this item represents the same printing as another, ignoring foil state.
    func matchesIgnoringFoil(_ other: CollectionItem) -> Bool {
        if let a = scryfallId, let b = other.scryfallId, !a.isEmpty, !b.isEmpty {
            return a == b
        }
        return title == other.title
            && edition == other.edition
            && collectorNumber == other.collectorNumber
    }

    /// Returns true when toggling foil would create a duplicate row among sibling items.
    func hasFoilCollision(in siblings: [CollectionItem]) -> Bool {
        let toggledFoil = !foil
        return siblings.contains { sibling in
            sibling.id != id && sibling.foil == toggledFoil && matchesIgnoringFoil(sibling)
        }
    }

    /// Toggles foil only when the target identity remains unique among sibling items.
    @discardableResult
    func toggleFoilIfNoDuplicate(in siblings: [CollectionItem]) -> Bool {
        guard !hasFoilCollision(in: siblings) else { return false }
        foil.toggle()
        return true
    }

    /// Toggles foil without any collision check.
    /// Used on the results page where users may legitimately hold both
    /// foil and non-foil copies of the same card in their inbox.
    func toggleFoilUnconditionally() {
        foil.toggle()
    }

    /// Create a copy of this item (for operations that need a standalone duplicate).
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
            cardKingdomUrl: cardKingdomUrl,
            colorIdentity: colorIdentity,
            priceRetail: priceRetail,
            priceBuy: priceBuy,
            quantity: quantity
        )
    }
}

@Model
public final class CardCollection {
    public var id: UUID
    public var name: String
    @Relationship(deleteRule: .cascade)
    public var items: [CollectionItem]
    public var createdAt: Date
    public var updatedAt: Date

    public init(name: String) {
        self.id = UUID()
        self.name = name
        self.items = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
public final class Deck {
    public var id: UUID
    public var name: String
    @Relationship(deleteRule: .cascade)
    public var items: [CollectionItem]
    public var createdAt: Date
    public var updatedAt: Date

    public init(name: String) {
        self.id = UUID()
        self.name = name
        self.items = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

extension Array where Element == CollectionItem {
    /// Sum of quantities across all items. Treats a stored quantity of 0 as 1 for migration safety.
    var totalQuantity: Int {
        reduce(0) { $0 + Swift.max(1, $1.quantity) }
    }
}

/// Merge `item` into `existingItems` if a matching card is found, otherwise insert as a new row.
///
/// The `assign` closure is called on the item only when it is newly inserted (no match found).
/// Use it to set the collection/deck relationship so it is never set before the duplicate check,
/// which would cause SwiftData to auto-track the item as a duplicate.
/// Returns the item that was updated or inserted.
@discardableResult
func mergeOrInsert(
    _ item: CollectionItem,
    into existingItems: [CollectionItem],
    context: ModelContext,
    assign: (CollectionItem) -> Void = { _ in }
) -> CollectionItem {
    if let existing = existingItems.first(where: { $0.matches(item) }) {
        existing.quantity += item.quantity
        return existing
    }
    assign(item)
    context.insert(item)
    return item
}
