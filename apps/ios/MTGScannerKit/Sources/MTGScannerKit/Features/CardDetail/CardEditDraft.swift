import Foundation
import SwiftData

@MainActor
@Observable
final class CardEditDraft {
    var printing: CardPrinting
    var isFoil: Bool
    var errorMessage: String?

    init(card: RecognizedCard, printing: CardPrinting? = nil) {
        let initialPrinting = printing ?? CardPrinting(card: card)
        self.printing = initialPrinting
        self.isFoil = initialPrinting.isFoilOnly
            || (!initialPrinting.isNonFoilOnly && (card.foil ?? false))
    }

    func select(_ printing: CardPrinting, foil: Bool) {
        self.printing = printing
        isFoil = printing.isFoilOnly || (!printing.isNonFoilOnly && foil)
    }

    func duplicates(for item: CollectionItem) -> [CollectionItem] {
        let siblings = item.collection?.items ?? item.deck?.items ?? []
        let candidate = CollectionItem(from: printing, foil: isFoil, quantity: item.quantity)
        return siblings.filter { $0.id != item.id && $0.matches(candidate) }
    }

    func save(item: CollectionItem, context: ModelContext, merge: Bool) -> Bool {
        let matches = duplicates(for: item)
        guard matches.isEmpty || merge else { return false }
        do {
            try context.save()
            item.apply(printing: printing, foil: isFoil)
            for match in matches {
                item.quantity += match.quantity
                context.delete(match)
            }
            item.collection?.updatedAt = Date()
            item.deck?.updatedAt = Date()
            try context.save()
            return true
        } catch {
            context.rollback()
            errorMessage = "Could not save changes. Please try again."
            return false
        }
    }
}

extension CardPrinting {
    init(card: RecognizedCard) {
        self.init(
            name: card.title ?? "Unknown card", setCode: card.setCode ?? "",
            setName: card.edition, collectorNumber: card.collectorNumber, rarity: card.rarity,
            typeLine: card.typeLine, oracleText: card.oracleText, manaCost: card.manaCost,
            power: card.power, toughness: card.toughness, loyalty: card.loyalty, defense: card.defense,
            scryfallId: card.scryfallId, imageUrl: card.imageUrl, setSymbolUrl: card.setSymbolUrl,
            cardKingdomUrl: card.cardKingdomUrl, cardKingdomFoilUrl: card.cardKingdomFoilUrl,
            colorIdentity: card.colorIdentity, finishes: nil
        )
    }
}

extension CollectionItem {
    func apply(printing: CardPrinting, foil: Bool) {
        let request = PriceFetchRequest(item: self)
        title = printing.name
        edition = printing.setName ?? printing.setCode
        setCode = printing.setCode
        collectorNumber = printing.collectorNumber
        self.foil = foil
        scryfallId = printing.scryfallId
        imageUrl = printing.imageUrl
        setSymbolUrl = printing.setSymbolUrl
        cardKingdomUrl = foil ? (printing.cardKingdomFoilUrl ?? printing.cardKingdomUrl) : printing.cardKingdomUrl
        colorIdentity = printing.colorIdentity
        applyRules(from: printing)
        if !request.matches(self) {
            clearPrices()
        }
    }

    private func applyRules(from printing: CardPrinting) {
        rarity = printing.rarity
        typeLine = printing.typeLine
        oracleText = printing.oracleText
        manaCost = printing.manaCost
        power = printing.power
        toughness = printing.toughness
        loyalty = printing.loyalty
        defense = printing.defense
    }
}
